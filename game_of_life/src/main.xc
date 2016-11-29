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
     int x[2]; //[0] is the start element and [1] is the last element
     int y[2];
 }coord;

typedef struct{
    char values[3][3]; //stores the array to work on with the neighbours, change the size of this later
    coord Span;   //stores the start of the values array in respect to the mother array
 } workercoord;



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

char numAliveNeighbors(char values[3][3], uchar flag) {
    char result = 0;
    for (int y = 0; y < 3; y++){
        for (int x = 0; x < 3; x++){
            if ((!(x==1&&y==1))&&values[y][x]==(uchar)255){
                result++;
            }
        }
    }
    if (flag ==1)
        return result;

    if (values[1][1]==255){
        if (result==2||result==3){
            return 255;
        }
        else {
            return 0;
        }
    }else {
        if (result==3){
            return 255;
        }
        else {
            return 0;
        }
    }

}

void worker(chanend distChan, streaming chanend collChan){
    uchar workToDo = 1;
    workercoord data;
    uchar result;
    uchar newChild[3][3];
    ////////send to collector a initial ready-for-work
    while(workToDo){
        select{
            case distChan :> data: ////////change to non array channel
                for (int y=0; y<3; y++){
                    newChild[y][0] = data.values[y][0];
                    newChild[y][2] = data.values[y][2];
                }
                for (int x=0; x<3; x++){
                    newChild[0][x] = data.values[0][x];
                    newChild[2][x] = data.values[2][x];
                }
                newChild[1][1] = numAliveNeighbors(data.values, 0);
                memcpy(data.values, newChild, 9 * sizeof(uchar));
                collChan <: data;
                uchar blabla = numAliveNeighbors(data.values, 1);
                printf ("Position:(%3.1d,%3.1d)  Alive:(%3.1d)  Neighbours:(%3.1d)  Result:(%3.1d)\n", data.Span.y[0], data.Span.x[0], data.values[1][1], blabla, result);
                break;

            case collChan :> workToDo:
                break;

        }
    }
    return;
}

void collector(streaming chanend worker[2], chanend output, streaming chanend distChan){
    uchar outArray[IMHT][IMWD];
    workercoord data;
    uchar finished;
    while(1){
        select {
            case worker[0] :> data:
                outArray[data.Span.y[0]][data.Span.x[0]] = data.values[1][1];
                break;
            case worker[1] :> data:
                outArray[data.Span.y[0]][data.Span.x[0]] = data.values[1][1];
                break;
            case distChan :> finished:
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
void distributor(chanend c_in, chanend workerChan[2], chanend fromAcc,streaming chanend colDist){

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );

  printf( "Waiting for Board Tilt...\n" );
  //int value;
  //fromAcc :> value;
  printf("got board tilt \n");

  int piecesleft = 1;
  uchar worker;
  workercoord childArray;  //worker & their cooredinates


  char pixels[IMHT][IMWD]; //This is the mother array

//Gets mother array from datain
  for( int y = 0; y < IMHT; y++ ) {
        for( int x = 0; x < IMWD; x++ ) {
            c_in :> pixels[y][x];
        }
  }


  childArray.Span.x[0]=0;
  childArray.Span.x[1]=0;
  childArray.Span.y[0]=0;
  childArray.Span.y[1]=0;


  while (piecesleft != 0){
      char a = 0;
      char b = 0;
      for( int y = -1; y <= 1; y++ ) {
          b=0;
              for( int x = -1; x <= 1; x++ ) {

                  childArray.values[a][b]= pixels[(childArray.Span.y[0]+y+IMHT)%(IMHT)][(childArray.Span.x[0]+x+IMWD)%(IMWD)];
                  b++;
              }
              a++;
          }

      colDist :> worker;
      workerChan[worker-1] <: childArray;

         /* case workerChan[1][0] :> workerRequest:
              current.worker = 1;
              colDist[0] <: current;
              workerChan[1][0] <: currentNeighbours;
              workerChan[1][0] <: current.coords;
              break;

*/

      childArray.Span.x[0]++;
      childArray.Span.x[1]++;
      if (childArray.Span.x[0] >= IMWD){
          childArray.Span.x[0] = 0;
          childArray.Span.x[1] = 0;
          childArray.Span.y[0]++;
          childArray.Span.y[1]++;
              if (childArray.Span.y[0] >= IMHT)
                  piecesleft = 0;
      }
  }

  /*
  workerChan[0][0] :> workerRequest;
  workerChan[0][1] <: (uchar) 0;
  workerChan[1][0] :> workerRequest;
  workerChan[1][1] <: (uchar) 0;*/
  colDist <: (uchar) 0;
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
    streaming chan colDist;
    chan distChan[2];


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
