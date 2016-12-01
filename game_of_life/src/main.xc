#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

typedef unsigned char uchar;

interface ledInterface{
    void update(char ledCode);
    void turnOffAll();
    void shutdown();
};
interface buttonInterface{
    void getButton(int buttonCode);
};
interface orientationInterface{
    void getOrientation(int orientation);
};
interface inputInterface{
    void getLastButton(int &button);
    void getLastOrientation(int &orientation);
    void shutdown();
};
interface readInterface{
    void readValue(uchar value);
};
interface writeInterface{
    void requestWrite();
    void writeValue(uchar value);
};


on tile[0] : out port leds = XS1_PORT_4F;
on tile[0] : in port buttons = XS1_PORT_4E;

char  inFileName[] = "256x256.pgm";
char outFileName[] = "testout.pgm";

#define IMWD 256
#define IMHT 256

#define LED_GREEN 0x04
#define LED_BLUE 0x02
#define LED_RED 0x08
#define LED_GREEN_SEPERATE 0x01


on tile[0] : port p_scl = XS1_PORT_1E;
on tile[0] : port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6


void ledProcess(out port ledPort, server interface ledInterface ledIF){
    char pattern = 0;
    while (1){
        select{
            case ledIF.update(char ledCode):
                pattern = pattern ^ ledCode;
                ledPort <: pattern;
                break;
            case ledIF.turnOffAll():
                ledPort <: 0x0;
                break;
            case ledIF.shutdown():
                ledPort <: 0;
                return;
        }
    }
}
void buttonProcess(in port buttonPort, client interface buttonInterface buttonIF){
    int r;
      while (1) {
        buttonPort when pinseq(15)  :> r;    // check that no button is pressed
        buttonPort when pinsneq(15) :> r;    // check if some buttons are pressed
        r-=12;
        buttonIF.getButton(r);
      }
}
void orientationProcess(client interface orientationInterface orientationIF, client interface i2c_master_if i2c){
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
        int x = 0;// read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

        //send signal to distributor after first tilt
        tilted = (x>30?1:0);
        orientationIF.getOrientation(tilted);
      }
}

void inputServer(server interface buttonInterface buttonIF, server interface orientationInterface orientationIF, server interface inputInterface inputIF){
    int lastButton = -1, lastOrientation = -1;
    while (1){
        select{
            case buttonIF.getButton(int button):
                lastButton = button;
                break;
            case orientationIF.getOrientation(int orientation):
                lastOrientation = orientation;
                break;
            case inputIF.getLastButton(int &button):
                button = lastButton;
                break;
            case inputIF.getLastOrientation(int &orientation):
                orientation = lastOrientation;
                break;
            case inputIF.shutdown():
                return;
        }
    }
}

void readFile(streaming chanend chanDist){
    int val;
    chanDist :> val;
    //printf( "Reading File Started!\n" );

    uchar line[ IMWD ];
    val = _openinpgm( inFileName, IMWD, IMHT );
    if( val ) {
        printf( "readFile: Error openening %s\n.", inFileName );
        return;
    }

    for( int y = 0; y < IMHT; y++ ) {
        _readinline( line, IMWD );
        for( int x = 0; x < IMWD; x++ ) {
            chanDist <: line[ x ];
        }
    }
    _closeinpgm();
    //printf( "Reading File Finished!\n" );
    return;
}
void writeToFile(streaming chanend chanDist){
    int val;
    chanDist :> val;
    //printf( "Writing File Started!\n" );

    uchar line[ IMWD ];
    val = _openoutpgm( outFileName, IMWD, IMHT );
    if( val ) {
        printf( "readFile: Error openening %s\n.", outFileName );
        return;
    }

    for( int y = 0; y < IMHT; y++ ) {
        for( int x = 0; x < IMWD; x++ ) {
            chanDist :> line[ x ];
            //printf( "%4.1d ", line[ x ] );
        }
        _writeoutline(line, IMWD);
        //printf( "   Line written\n" );
    }
    _closeoutpgm();
    //printf( "Writing File Finished!\n" );
    return;
}

void worker(streaming chanend chanDist, streaming chanend neighbor){
    int continueProcessing;
    int CHHT = IMHT, CHWD = IMWD/2;
    uchar chunk[IMHT+2][IMWD/2+2];

    while (1){
        //check if the distributor wants to stop
        chanDist :> continueProcessing;
        if (continueProcessing == 0){return;}

        //recieve from distributor
        for (int y = 1; y<=CHHT; y++){
            for(int x = 1; x<=CHWD; x++){
                chanDist :> chunk[y][x];
            }
            neighbor <: chunk[y][1];
            neighbor <: chunk[y][IMHT/2];
            neighbor :> chunk[y][(IMHT/2)+1];
            neighbor :> chunk[y][0];
        }
        for (int i = 0; i<CHWD+2;i++){
            chunk[0][i]    = chunk[CHHT][i];
            chunk[CHHT+1][i] = chunk[1][i];
        }

        //calculate and send back to distributor
        int neighbors;
        uchar returnValue;
        for (int y = 1; y<=CHHT;y++){
            for (int x = 1; x<=CHWD;x++){
                neighbors = (chunk[y-1][x-1]+chunk[y-1][x  ]+chunk[y-1][x+1]+
                             chunk[y  ][x-1]+                chunk[y  ][x+1]+
                             chunk[y+1][x-1]+chunk[y+1][x  ]+chunk[y+1][x+1])/255;
                if (chunk[y][x] == 255){
                    returnValue = ((neighbors==2||neighbors==3)?255:0);
                    //printf("alive: (%2.1d,%2.1d): %d, %3.1d\n",x,y,neighbors,returnValue);
                } else {
                    returnValue = ((neighbors==3)?255:0);
                    //printf(" dead: (%2.1d,%2.1d): %d, %3.1d\n",x,y,neighbors,returnValue);
                }
                chanDist <: returnValue;
            }
        }
    }
}

void distributor(streaming chanend distRead, streaming chanend distWrite,
                 client interface ledInterface ledIF, client interface inputInterface inputIF,
                 streaming chanend chanWorker[2]){

    int lastButton = -1; //stores the last button press sent to
    int lastOrientation = -1;
    printf("please press SW1 to begin processing\n");
    do{ //waits for a specific button press before continuing
        inputIF.getLastButton(lastButton);
    }while (lastButton != 2);

    int roundCount = 0; //incremented every time a round of processing happens
    int debug = 0; //enables printing the board every round


    timer readTimer, processTimer, writeTimer, totalTimer;
    uint32_t timeStart, timeStop, timeRead, timeProcess, timeWrite, timeTotalStart, timeTotalStop, timeTotal;
    uchar currentBoard[IMHT][IMWD];


    //read board from file on the first round
    ledIF.update(LED_GREEN);//reader LED on
    readTimer :> timeStart;//start the readTimer
    distRead <: (int) 1;// start the reader process
    for(int y = 0; y < IMHT; y++){
        for(int x = 0; x < IMWD; x++){
            distRead :> currentBoard[y][x];
        }
    }

    //stop timer and save difference in timeRead
    readTimer :> timeStop;
    timeRead = timeStop - timeStart;

    //printf("finished reading!\n");
    ledIF.update(LED_GREEN); // reader LED off

    totalTimer :> timeTotalStart;
    do{
        roundCount++;

        //wait for orientation to be correct before continuing and change LED to show paused
        inputIF.getLastOrientation(lastOrientation);
        if (lastOrientation!=0){
            ledIF.update(LED_RED);
            while(lastOrientation!=0){ inputIF.getLastOrientation(lastOrientation); }
            ledIF.update(LED_RED);
        }

        //for debugging, print board
        if (debug == 1){
            for(int y = 0; y < IMHT; y++){
                for(int x = 0; x < IMWD; x++){
                    printf("%4.1d ",currentBoard[y][x]);
                }
                printf("\n");
            }
            printf("processing round starting\n");
        }

        //update led to show processing
        ledIF.update(LED_GREEN_SEPERATE);

        //starts process timer
        processTimer :> timeStart;

        //alert workers that we are continuing
        for(int i = 0; i<2; i++){ chanWorker[i] <: (int) 1; }

        //send data to relevant workers
        for(int y = 0; y < IMHT; y++){
            for(int x = 0; x < IMWD; x++){
                if (x<IMWD/2){
                    chanWorker[0] <: currentBoard[y][x];
                } else {
                    chanWorker[1] <: currentBoard[y][x];
                }
            }
        }

        int count[2] = {0,0}; //used to see how many pieces of data have been sent from each worker
        int inX, inY; //used for calculating each workers current xy pointer
        uchar inputValue; //holds the incoming data

        //retrieve data from workers and store it in currentBoard
        while (count[0]+count[1] < IMHT*IMWD){
            select{
                case chanWorker[0] :> inputValue:
                    inX = count[0]%(IMWD/2); inY = (count[0] - inX)/(IMHT);
                    currentBoard[inY][inX] = inputValue;
                    count[0]++;
                    break;
                case chanWorker[1] :> inputValue:
                    inX = count[1]%(IMWD/2); inY = (count[1] - inX)/(IMHT);
                    currentBoard[inY][inX+IMWD/2] = inputValue;
                    count[1]++;
                    break;
            }
        }

        processTimer :> timeStop;
        timeProcess = timeStop - timeStart;
        inputIF.getLastButton(lastButton);

    } while (roundCount < 100 && lastButton != 1);

    //stop timer for amount of rounds
    totalTimer :> timeTotalStop;
    timeTotal = timeTotalStop - timeTotalStart;

    //printf("SW2 pressed, saving to file!\n");
    //printf("rounds completed: %d\n", roundCount);
    ledIF.turnOffAll();
    ledIF.update(LED_BLUE);

    //let the workers know to shutdown
    for(int i = 0; i<2; i++){chanWorker[i] <: (int) 0;}

    //start write timer
    writeTimer :> timeStart;

    //write to file
    distWrite <: (int) 1;
    for(int y = 0; y < IMHT; y++){
        for(int x = 0; x < IMWD; x++){
            distWrite <: currentBoard[y][x];
        }
    }

    //stop timer and store
    writeTimer :> timeStop;
    timeWrite = timeStop - timeStart;

    ledIF.turnOffAll();
    ledIF.shutdown();


    printf("===========Timing===========\n"
           "    Read: %11u ticks\n"
           " 1 round: %11u ticks\n"
           "   Write: %11u ticks\n"
           "   Total: %11u ticks\n",
           timeRead,timeProcess,timeWrite, timeTotal);
    return;

}

int main (void){
    interface ledInterface ledIF;
    interface buttonInterface buttonIF;
    interface orientationInterface orientationIF;
    interface inputInterface inputIF;

    streaming chan distRead, distWrite, distWorkers[2], chanWorkers;
    i2c_master_if i2c[1];

    par {
        on tile[0] : ledProcess(leds, ledIF);
        on tile[0] : buttonProcess(buttons, buttonIF);
        on tile[0] : orientationProcess(orientationIF,i2c[0]);
        on tile[0] : inputServer(buttonIF, orientationIF, inputIF);
        on tile[0] : i2c_master(i2c, 1, p_scl, p_sda, 10);
        on tile[0] : readFile(distRead);
        on tile[0] : writeToFile(distWrite);
        on tile[0] : distributor(distRead, distWrite, ledIF, inputIF, distWorkers);

        on tile[1] : worker(distWorkers[0],chanWorkers);
        on tile[1] : worker(distWorkers[1],chanWorkers);

    }
    return 0;
}
