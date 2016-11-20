// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width

typedef unsigned char uchar;      //using uchar as shorthand
typedef struct{
    uchar val;
    int x;
    int y;
} pixel;

port p_scl = XS1_PORT_1E;         //interface ports to orientation
port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
      //printf( "%d ", line[ x ] ); //show image values
    }
    printf( "\n" );
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}

void worker(chanend cDist, streaming chanend cColl, streaming chanend cNeigh){
    uchar pixels[IMWD/2+2][IMHT];
    for( int y = 0; y < IMHT; y++ ) {
          for( int x = 1; x <=IMWD/2; x++ ) {
              cDist :> pixels[x][y];
              //printf("%c, ", pixels[x][y]);
          }
          cNeigh <: pixels[0][y];
          cNeigh <: pixels[IMHT/2][y];
          cNeigh :> pixels[IMHT/2][y];
          cNeigh :> pixels[0][y];
    }


    pixel current;
    int neighbors;
    for( int y = 0; y < IMHT; y++ ) {   //go through all lines
        for( int x = 0; x < IMWD; x++ ) {
            current.x = x;
            current.y = y;
            current.val = pixels[x][y];
            neighbors = pixels[(x+IMHT+1)%IMHT] [(y+IMHT+1)%IMHT] +
                            pixels[(x+IMHT+1)%IMHT] [(y+IMHT)%IMHT] +
                            pixels[(x+IMHT+1)%IMHT] [(y+IMHT-1)%IMHT] +
                            pixels[(x+IMHT-1)%IMHT] [(y+IMHT+1)%IMHT] +
                            pixels[(x+IMHT-1)%IMHT] [(y+IMHT)  %IMHT] +
                            pixels[(x+IMHT-1)%IMHT] [(y+IMHT-1)%IMHT] +
                            pixels[(x+IMHT  )%IMHT] [(y+IMHT+1)%IMHT] +
                            pixels[(x+IMHT  )%IMHT] [(y+IMHT-1)%IMHT];
            if (current.val == 255){
                current.val = (neighbors/255==2||neighbors/255==3?255:0);
            } else {
                current.val = (neighbors/255==3?255:0);
            }
            cColl <: current;
          //send some modified pixel out
        }
      }
}
void collector(streaming chanend worker[2], chanend output){
    int count = 0;
    uchar outArray[IMWD][IMHT];
    pixel inPixel;
    while(count < IMHT*IMWD){
        select {
            case worker[0] :> inPixel:
                printf("recieved pixel: %d \n", inPixel.val);
                outArray[inPixel.x][inPixel.y] = inPixel.val;
                count++;
                break;
            case worker[1] :> inPixel:
                printf("recieved pixel: %d \n", inPixel.val);
                outArray[inPixel.x][inPixel.y] = inPixel.val;
                count++;
                break;
            }
    }
    for( int y = 0; y < IMHT; y++ ) {
        for( int x = 0; x < IMWD; x++ ) {
          output <: outArray[x][y];
        }
      }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend distChan[2], chanend fromAcc)
{

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );

  printf( "Waiting for Board Tilt...\n" );
  int value;
  fromAcc :> value;
  printf("got board tilt \n");
  uchar current;
  for( int y = 0; y < IMHT; y++ ) {
      for( int x = 0; x < IMWD; x++ ) {
          c_in :> current;
          if(x<IMWD/2){
              distChan[0] <: current;
          } else {
              distChan[1] <: current;
          }
      }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  //Open PGM file
  printf( "DataOutStream: Start...\n" );
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream: Error opening %s\n.", outfname );
    return;
  }

  //Compile each line of the image and write the image line-by-line
  for( int y = 0; y < IMHT; y++ ) {
    for( int x = 0; x < IMWD; x++ ) {
      c_in :> line[ x ];
      printf( "-%4.1d ", line[ x ] ); //show image values
    }
    _writeoutline( line, IMWD );
    printf( "DataOutStream: Line written...\n" );
  }

  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the orientation x-axis forever
  while (1) {

    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (!tilted) {
      if (x>30) {
        tilted = 1 - tilted;
        toDist <: 1;
      }
    }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

    i2c_master_if i2c[1];               //interface to orientation

    char infname[] = "test.pgm";     //put your input image path here
    char outfname[] = "testout.pgm"; //put your output image path here
    chan c_inIO, c_outIO, c_control;    //extend your channel definitions here
    streaming chan workerChan;
    streaming chan collChan[2];
    chan distChan[2];

    par{
        worker(distChan[0], collChan[0], workerChan);
        worker(distChan[1], collChan[1], workerChan);
        collector(collChan, c_outIO);
        i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
        orientation(i2c[0],c_control);        //client thread reading orientation data
        DataInStream(infname, c_inIO);          //thread to read in a PGM image
        DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
        distributor(c_inIO, distChan, c_control);//thread to coordinate work on image
    }

  return 0;
}
