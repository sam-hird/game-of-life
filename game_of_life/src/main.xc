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

typedef struct{
     int x;
     int y;
 }coord;

typedef struct{
     uchar worker;
     coord coords;
 } workercoord;

typedef struct{
    char values[3][3];
} neighbours;


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
void DataInStream(char infname[], chanend c_out, chanend toOut)
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
      //printf( "%4.1d ", line[ x ] );
    }
    //printf("\n");
  }

  //Close PGM image file
  _closeinpgm();
  toOut <: 1;
  printf( "DataInStream: Done...\n" );
  return;
}

char numAliveNeighbors(char values[3][3]) {
    char result = 0;
    for (int y = 0; y < 3; y++){
        for (int x = 0; x < 3; x++){
            if ((!(x==1&&y==1))&&values[y][x]==(uchar)255){
                result++;

            }
        }
    }
    return result;
}

void worker(chanend distChan[2], streaming chanend collChan){
    uchar workToDo = 1;
    neighbours data;
    coord location;
    char livingNeighbors;
    uchar request = 1;
    uchar result;
    while(workToDo){
        distChan[0] <: request;
        select{
            case distChan[0] :> data:
                distChan[0] :> location;
                livingNeighbors = numAliveNeighbors(data.values);
                if (data.values[1][1]==255){
                    if (livingNeighbors==2||livingNeighbors==3){
                        result = 255;
                        collChan <: (uchar) result;
                    }
                    else {
                        result = 0;
                        collChan <: (uchar) result;
                    }
                }else {
                    if (livingNeighbors==3){
                        result = 255;
                        collChan <: (uchar) result;
                    }
                    else {
                        result = 0;
                        collChan <: (uchar) result;
                    }
                } printf ("Position:(%3.1d,%3.1d)  Alive:(%3.1d)  Neighbours:(%3.1d)  Result:(%3.1d)\n", location.x, location.y, data.values[2][2], livingNeighbors, result);
                break;

            case distChan[1] :> workToDo:
                break;
        }
    }
    return;
}

void collector(streaming chanend worker[2], chanend output, chanend distChan[2]){
    uchar outArray[IMHT][IMWD];
    uchar inputValue[2];
    workercoord workerLocation[3];
    uchar finished;
    while(1){
        select {
            case worker[0] :> inputValue[0]:
                outArray[workerLocation[0].coords.y][workerLocation[0].coords.x] = inputValue[0];
                break;
            case worker[1] :> inputValue[1]:
                outArray[workerLocation[1].coords.y][workerLocation[1].coords.x] = inputValue[1];
                break;
            case distChan[0] :> workerLocation[2]:
                workerLocation[workerLocation[2].worker] = workerLocation[2];
                break;
            case distChan[1] :> finished:
            for( int y = 0; y < IMHT; y++ ) {
                for( int x = 0; x < IMWD; x++ ) {
                  output <: outArray[y][x];
                }
            }
                return;
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
void distributor(chanend c_in, chanend workerChan[2][2], chanend fromAcc, chanend colDist[2]){

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );

  printf( "Waiting for Board Tilt...\n" );
  //int value;
  //fromAcc :> value;
  printf("got board tilt \n");

  int piecesleft = 1;
  uchar workerRequest;
  neighbours currentNeighbours;
  workercoord current;

  char pixels[IMHT][IMWD];

  current.coords.x=0;
  current.coords.y=0;
  for( int y = 0; y < IMHT; y++ ) {
        for( int x = 0; x < IMWD; x++ ) {
            c_in :> pixels[y][x];
        }
    }

  while (piecesleft != 0){
      char a = 0;
      char b = 0;
      for( int y = -1; y <= 1; y++ ) {
          b=0;
              for( int x = -1; x <= 1; x++ ) {

                  currentNeighbours.values[a][b]= pixels[(current.coords.y+y+IMHT)%(IMHT)][(current.coords.x+x+IMWD)%(IMWD)];
                  b++;
              }
              a++;
          }
      select {
          case workerChan[0][0] :> workerRequest:
              current.worker = 0;
              colDist[0] <: current;
              workerChan[0][0] <: currentNeighbours;
              workerChan[0][0] <: current.coords;
              break;

          case workerChan[1][0] :> workerRequest:
              current.worker = 1;
              colDist[0] <: current;
              workerChan[1][0] <: currentNeighbours;
              workerChan[1][0] <: current.coords;
              break;
      }

      current.coords.x++;
      if (current.coords.x >= IMWD){
          current.coords.x = 0;
          current.coords.y ++;
              if (current.coords.y >= IMHT)
                  piecesleft = 0;
      }
  }
  workerChan[0][0] :> workerRequest;
  workerChan[0][1] <: (uchar) 0;
  workerChan[1][0] :> workerRequest;
  workerChan[1][1] <: (uchar) 0;
  colDist[1] <: (uchar) 0;
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in, chanend fromIn)
{
  int res;
  uchar line[ IMWD ];
  int done;
  fromIn :> done;
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
      printf( "%4.1d ", line[ x ] ); //show image values
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
        return;
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
    chan c_inIO, c_outIO, c_control, inOut;    //extend your channel definitions here
    streaming chan collChan[2];
    chan distChan[2][2];
    chan colDist[2];

    for (int i =0;i<1;i++){
        par{
            worker(distChan[0], collChan[0]);
            worker(distChan[1], collChan[1]);
            collector(collChan, c_outIO, colDist);
            //i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
            //orientation(i2c[0],c_control);        //client thread reading orientation data
            DataInStream(infname, c_inIO, inOut);          //thread to read in a PGM image
            DataOutStream(outfname, c_outIO, inOut);       //thread to write out a PGM image
            distributor(c_inIO, distChan, c_control, colDist); //thread to coordinate work on image
        }
    }

  return 0;
}
