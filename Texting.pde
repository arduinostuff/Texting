/*
 Sketch for receiving SMS and displaying these on 4x20 LCD 
 Also, ability to reply with a simple YES or NO message
 Also, various other features, see descriptions in comments below
 */

//---- Pin definitions
// Serial communication with GSM on Pin 0-1
// Device buttons connected to Pin 2-5
// Beeper and "new message" indicator on Pin 6 & 13
// LED conneced to Pin 7-12
#define YESbutton 2
#define NObutton 3
#define CALLbutton 4
#define ACKbutton 5
#define BEEPERpin 6
#define LCD1 7
#define LCD2 8
#define LCD3 9
#define LCD4 10
#define LCD5 11
#define LCD6 12
#define LEDpin 13
#define LCDonoff A0   // controls the LCD backlight


//---- Libraries
#include <LiquidCrystal.h>
#include <EEPROM.h>


//---- LCD
LiquidCrystal lcd(LCD1,LCD2,LCD3,LCD4,LCD5,LCD6);         
#define LCDrows 4            // 4 LCD rows 
#define rowLength 20         // 20 characters per LCD row


//---- loopState - Controls the procesng
#define  Xidle 0              //Nothing showing on display, no messaging in progress
#define  Xwaitfornumber 1     //Sent a request to GSM and waiting for response
#define  Xnewmessage 2        //There was a new message in the response
#define  Xerror 3             //Received message is erroneous
#define  Xunpack 4            //Unpacking the received message
#define  Xdisplayheader 5     //The message was a real SMS - display it
#define  Xspecial 6           //The message was a config message - process it but no display
#define  Xsmsonscreen 7       //Unread (i.e. 'uncleared') message is currently showing on screen
#define  Xdisplaymessage 8    //Unread (i.e. 'uncleared') message is currently showing on screen
#define  Xheaderonscreen 9    //Header of unread message is currently showing on screen
byte loopState = Xidle;       //Current state - one of the above


//---- Various time information
float now;                       //current time
float lastRead;                  //last time reading from GSM was made
float buttonTime;                //time for latest button pressing
#define readPeriod 5000          //checking for new messages every 5 sec


//---- Screensave information
float screensaveTime;            //screen will go dark at screensaveTime
boolean screenSaving;            //true if screen is dark due to screensaving
#define timeoutmax 20000        //screensaving after 20 sec


//---- String STR for received bytes from GSM
//   STRix indicates the insertion point, i.e. where next
//   received character should be inserted
//
//   Read from & write to STR is done via these functions:
//   STRRESET   --- "Clears" the string, i.e. resets STRix to
//                  point at start of string
//   STRADD     --- Adds a byte at [STRix]
//   STRFINDB   --- Looks for a substring within STR, 
//                  starting from [STRix], going towards [0]
//   STRFINDF   --- Looks for a substring within STR,
//                  starting from a certain index and
//                  going towards end of STR
//   STRINDEXOF --- Looks for a (char) within STR, starting from
//                  a certain index, going towards end of STR
//
String STR = "------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------";
// Next byte is written to STR[STRix]
int STRix = 0;                    
// STR is 200 byte long; At 190th byte received, EOM bytes
// are inserted and the rest of incoming message is ignored
#define STRlengthmax 190          


//---- Index within SIM card message storage, i.e. an index (1-30)
//     within the SIM message storage  
int msgToRead;       
#define msgMax 30                 // Max message number in SIM


//---- Months
char* monthNames [] =   {
  "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"};


//---- Current SMS is unpacked and stored in RAM
//     Each component of the SMS in its own variable
int SMSstart;            // points at start of received string 
int SMSend;              // points at end of received string
int SMScsum;             //Checksum of sender's phone number
String SMSnumber = "";   // Sender's number
String SMSdateTime = ""; // Date & Time for receiving message 
String SMSmessage = "";  // Actual text message
boolean USformat;        // US format is '+1nnnyyyyyyy' 
String PBname = "------------";   // Name from Phonebook
String LCDnumber = "";   // The sender number as displayed


//---- Indicates which button was pressed
byte whichButton;            
#define notPressed 0  // whichButton is 0 if nothing pressed


//---- EEPROM storage for Phonebok information
// The #define below define the structure of the EEPROM storage
//0 - 3   ... a 4-digit pin code
//9       ... which of the phonebook entries (10-39) that is the 'main contact'
//10 - 39 ... eeprom[n] is a checksum value if name defined and FF if not defined
//40-61   ... 22 byte, number&name for 1st phonebook entry
//   40-51   ... Phone number
//   52-61   ... Name
//62-84 ... 2nd Phonebook entry
//etc
#define EpinAt 0        // EEPROM[0] = start of 4-digit pincode 
#define EcontactAt 9    // EEPROM[9] is a value from 10 to 39
#define EnamelistAt 10  // Start of checksum info at EEPROM[10]
#define EnamelistNbr 30 // 30 Names can be stored
#define EnamesAt 40     // First name record in EEPROM[40]
#define EnamenbrLth 22  // Length of number + name
#define EnumberLth 10   // Length of number
#define EnameLth 12     // Length of name


//---- EEPROM-phone book variables
// PIN is read from EEPROM into this variable
String correctPIN = "----";            

// A copy of EEPROM[10] - EEPROM[39]
byte checksumList [EnamelistNbr];      

// The 12-digit number (incl"+1") to receive "call me" message
String CONTACTnumber = "------------"; 


//---- Indicates type of received special phonebook message
# define SPcontact 101
# define SPname 102
int SPmessage;


//---- Definition of Beeper melody
#define Tone1 262
#define Tone2 247
#define Tone3 220
#define Tone4 196
#define beepLength 250
#define beepPause 300


/*
*********************************
 SETUP
 Immediately after power on, GSM starts sending information to
 Arduino. The first part of the Setup processing is 
 to receive and analyze those messages. 
 */
void setup() {

  // --- Various information for processing what is 
  //     received from GSM
  boolean found;   // 'true' when we find what we're waiting for
  int indexGSM;    // used for checking what was received
  byte readByte;   // one byte read from GSM
  int loopcounter; // counts reading cycles

  // --- byte for EEPROM read/write   
  byte EEbyte;         

  // --- Setting up communication
  Serial.begin(9600); // --- GSM talks via SERIAL
  lcd.begin(20,4);    // --- LCD is 4x20 characters

  // --- Define & Initiate buttons, LED, Beeper
  pinMode(YESbutton, INPUT);
  pinMode(NObutton, INPUT);
  pinMode(ACKbutton, INPUT);
  pinMode(CALLbutton, INPUT);
  pinMode(LEDpin, OUTPUT);
  pinMode(BEEPERpin, OUTPUT);
  pinMode(LCDonoff, OUTPUT);

  digitalWrite(YESbutton, HIGH);
  digitalWrite(NObutton, HIGH);
  digitalWrite(ACKbutton, HIGH);
  digitalWrite(CALLbutton, HIGH);


  // --- LCD initialization
  CLEARSCREEN(); // Blank screen
  LIGHTSON();    // turns on the display
  SETROW(2);     // Cursor to second row
  lcd.print("STARTING...");

  // --- GSM Setup
  // GSM unit requires several rounds of message interaction at
  // power on. 
  // Commands to GSM are typically of format 
  //               'AT+[command]=[parameter]'
  // and terminated by <cr>, i.e. [0x0d]
  // 
  // Response will be <cr><lf>OK<cr><lf> and possibly other
  // data as well.
  //
  // For each command, the setup routine waits for the "OK" before processing continues.
  // If no 'OK' is returned, the command has failed
  //
  // At power up, GSM will send a few status messages 
  // The sketch waits for all of these to arrive.
  // When "+SIND: 4" has been received, the GSM unit is ready
  // for action.
  // 
  // Note that Arduino Reset does not bring the GSM back to
  // a restarted "fresh" state

  STRRESET(); //Reset receiving string
  found = false;
  loopcounter=0;

  // --- Waiting for "+SIND: 4" from GSM
  while (found == false) {
    if(Serial.available() >0)
    {
      //Get the character from the GSM serial port
      readByte=Serial.read();
      loopcounter++;    
      STRADD(readByte);       // Move byte into STR string

      if (loopcounter>100){   
        // No need to check received info until after 100th byte
        //
        // indexGSM >0 means we found the expected message
        //
        // Next, see if more bytes are coming in, then check
        // if GSM is reporting anything else, such as..
        //     SIND:7 = Network not available, e.g bad antenna
        //     SIND:8 = situations like poor network coverage
        // Other "SIND" responses do not trigger LCD error message

        indexGSM = STRFINDB("+SIND: 4");  // >0 if SIND4 received
        if (indexGSM >0) {
          //found the 'ready' message
          //look for more incoming bytes
          for (int x = 0;x<30000;x++){          
            if(Serial.available() >0){
              readByte=Serial.read();
              STRADD(readByte);
            }
          }
          found = true;
        }
        // If we get here, we checked serial link 30000 times
        // witout receiving SIND: 4
        // something is not right with the HW or network 
        // now check what's wrong, i.e. if SIND: 7 or SIND: 8 
        // are received. 
        // In any case, we will not leave this while loop unless
        // receiving "SIND: 4"
        //
        indexGSM = STRFINDB("+SIND: 7");  
        if (indexGSM>0) { //SIND7 received - service unavailable
          SETROW(1);
          lcd.print("SERVICE UNAVAILABLE");
          found = false;
          delay(3000);
          CLEARSCREEN();
        }

        indexGSM = STRFINDB("+SIND: 8");  
        if (indexGSM>0) { //SIND8 received - no network
          SETROW(1);
          lcd.print("NO NETWORK ACCESS");
          found = false;
          delay(3000);
          CLEARSCREEN();
        }
      }
    }
  }//end of wait for SIND:4
  // When we get here, GSM is ready to receive orders

  // Some of the orders below are not completely necessary,
  // since GSM unit remembers settings since last run
  // ..... but no harm doing it again.

  // --- Set GSM band 
  //SBAND=7 to define GSM band used in the US. 
  STRRESET(); 
  Serial.flush();
  Serial.print("AT+SBAND=7");
  Serial.print(0x0D,BYTE);  //<cr>
  READFROMGSM();   // Wait for "OK" reply from GSM

    // --- Set Baud rate
  STRRESET(); 
  Serial.flush();
  Serial.print("AT+IPR=9600");
  Serial.print(0x0D,BYTE);  //<cr>
  READFROMGSM();   // Wait for "OK" reply from GSM

    // --- GSM "text" mode
  // Command "AT+CMGF=1" sets GSM up to interact in "text" mode.  
  STRRESET(); 
  Serial.flush();
  delay (500);     // Not sure why, but this helps
  Serial.print("AT+CMGF=1");
  Serial.print(0x0D,BYTE);  //<cr>
  READFROMGSM();   // Wait for "OK" reply from GSM

    // --- SIM storage 
  // Command " AT+CPMS="SM","SM" defines SMS storage to be the SIM card
  STRRESET(); 
  Serial.flush();
  Serial.print("AT+CPMS=");
  Serial.print(0x22,BYTE);  // "
  Serial.print("SM");  
  Serial.print(0x22,BYTE);  // "
  Serial.print(",");
  Serial.print(0x22,BYTE);  // "
  Serial.print("SM");  
  Serial.print(0x22,BYTE);  // "
  Serial.print(0x0D,BYTE);  //<cr>
  READFROMGSM();   // Wait for "OK" reply from GSM


    // That's it for GSM initialization
  // Now, some EEPRM processing

  // --- PIN code
  // Read from EEPROM - If not available, create random PIN 
  // and store in EEPROM
  EEbyte = EEPROM.read(EpinAt);
  if (EEbyte == 255){
    //EEPROM not populated yet
    //Set PIN to 4-digit random value
    randomSeed(analogRead(0));
    for (int x=0;x<=3;x++){
      EEbyte = random(0,9)+48;      // between char '0' and char '9'
      EEPROM.write(EpinAt+x,EEbyte);  
      correctPIN[x] = char(EEbyte); // keep in memory as well
    }
  }
  else {
    //read PIN info from EEPROM
    for (int x=0;x<4;x++){
      EEbyte = EEPROM.read(EpinAt+x);
      correctPIN[x] = char(EEbyte);
    }

    //Namelist info
    //Each phonebook entry has a 'checksum' defined, for easier
    //search for a match between caller's number and phonebook
    //entries. 
    //These checksum bytes (1 byte per phonebook entry) are 
    //stored in EEPROM but reside in RAM during operation
    for (int x=0;x<EnamelistNbr;x++){
      checksumList[x] = EEPROM.read(EnamelistAt+x);
    }
  } 

  // Phone number for main contact read from EEPROM into RAM
  EEbyte = EEPROM.read(EcontactAt);
  if (EEbyte >= 0 && EEbyte < EnamelistNbr){
    //Contact is defined - read it from EEPROM
    readByte = EEPROM.read(EnamelistAt+EEbyte);
    if (readByte != 0xFF){
      //store as "+11231234567"
      CONTACTnumber[0] = '+';
      CONTACTnumber[1] = '1';
      for (int x = 0;x<EnumberLth;x++){
        readByte = EEPROM.read(EnamesAt+EEbyte*EnamenbrLth+x);
        CONTACTnumber[x+2] = readByte;
      }
    }
  }


  // --- Startup is completed. 
  // Say so on screen, and display PIN code as well
  Serial.flush();
  CLEARSCREEN();
  lcd.print("STARTUP COMPLETE");
  SETROW(3);
  lcd.print("    PIN-CODE:");
  SETROW(4);
  lcd.print("      ");
  lcd.print(correctPIN);
  delay(3000);
  CLEARSCREEN();


  // --- Some final preparations:
  // loop initiation
  loopState = Xidle;

  // set screen saver
  // screen will go dark when time = screensaveTime
  screensaveTime = millis()+timeoutmax;  
  screenSaving = false;

  // lastRead=0 forces a check whether GSM has 
  // received new messages
  lastRead = 0;      
}


/*
*********************************
 LOOP
 The loop does the following:
 1) anynewmessage --- Check whether new message from GSM
 2) receiving --- If so, read the message string from GSM
 3) unpack --- Unpack and analyze the received string
 4) special --- Process the 'special' messages, if any
 5) lcddisplay --- Display what's received on screen
 6) buttons --- processing of button pressing
 7) screensave --- turn of screen if nothing has happened in a while
 
 loopState defines the current overall state of the processing
 */

void loop(){
  ANYNEWMESSAGE(); // Check if any new SMS message
  RECEIVING();     // If so, read from GSM
  UNPACK();        // Process the received message (if any)
  SPECIAL();       // Deal with special message (if received)
  LCDDISPLAY();    // Display information (if anything received)
  BUTTONS();       // Process input (if buttons pressed)
  SCREENSAVE();    // Screen saver after timeout period
}//end loop

/*
*********************************
 ANYNEWMESSAGE
 The CPMS AT command reads number of messages stored in SIM
 If a message is available, read it in and process it in RECEIVING
 
 In SIM, messages are numbered 1 - 30.
 Messages are deleted from SIM after reading, 
 Current number of messages in SIM is checked periodically
 When the number goes up, we read from all message indices (1-30)
 until we find a valid message. Typically, the new message will
 be in #1 position in the SIM memory, but it
 (and additional messages) may be anywhere 1-30
 */
void ANYNEWMESSAGE(){
  if (loopState == Xidle) {
    // Read number of stored messages (if time to do so)
    now = millis();
    if (now-lastRead >= readPeriod) {
      // time to read - reset in-buffer & send read order
      STRRESET();   //reset in-buffer string
      Serial.flush();
      // AT command for "read number of messages stored in SIM
      Serial.print("AT+CPMS?");    
      Serial.print(0x0D,BYTE);  //<cr>
      // RECEIVING waits for a response in next loop cycle
      loopState = Xwaitfornumber;
      lastRead = millis();
    }
  }
}//end anynewmessage


/*
*********************************
 RECEIVING
 Reads one message from SIM, waits for response and unpacks
 the received information. The process depends on 'loopState':
 
 Xwaitfornumber --- Waiting for GSM response re. number of
 messages stored in SIM. If number > 0 (ie new message received), 
 transition to Xnewmessage in following loop cycle.
 
 Xnewmessage --- Order reading of one message from GSM and 
 receive the reply. Received info is processed in UNPACK.  
 
 In some cases, the processing goes to Xerror, where basic
 error handling (e.g. removing corrupted SMS) takes place.  
 
 If loopState == other than the above, no action in RECEIVING
 */
void RECEIVING(){
  int byteindex;  // used for checking what was received
  int startpoint; // used for checking what was received
  int endpoint;   // used for checking what was received
  char inByte;    // byte from STR
  int msgNumber;  // Number of messages in SIM storage
  boolean more;   // Used for breaking out of loops

  switch (loopState){
  case Xwaitfornumber:  
    // Receiving number of messages in SIM  
    {
      READFROMGSM();  // Read from GSM into STR string. 
      //  After return from READFROMGSM, STR should contain
      // a string such as 
      //         +CPMS: "SM",NN,30,"SM",NN,30"<cr><lf><cr>
      //         <lf>OK<cr><lf>
      //  where the first "NN" is the number of messages in SIM

        //look for "CPMS" in STR string
      byteindex = STRFINDF("CPMS",0);  
      if (byteindex == -1){
        // incorrect information returned
        // flush in-buffer and read again in future cycle
        Serial.flush();
        loopState = Xidle;
        lastRead = millis();
      }
      else {
        //a response to the 'CPMS' command is received
        //find the number of messages in SIM
        startpoint = STRINDEXOF(',', byteindex);   
        byteindex = startpoint+1;
        endpoint = STRINDEXOF(',', byteindex); 
        //[startpoint] and [endpoint] point at the 
        //two commas bracketing the number

        msgNumber = 0;
        // convert NN to a value 0-30
        for (int x = startpoint+1; x<endpoint;x++){
          msgNumber = msgNumber*10;
          inByte = STR[x];
          msgNumber = msgNumber + inByte-'0';  
        }

        if (msgNumber > 0){
          // New message exists - process it in next loop cycle
          loopState = Xnewmessage;  
          msgToRead = 1;
        }
        else {
          loopState = Xidle;  // Go back to idle
        }//end if
        break;
      }
    }//end waitfornumber

  case Xnewmessage:
    // Read one message from SIM
    // message number is in 'msgToRead' 
    // If the number is e.g. 6, AT command for 
    // reading message #6 would be "AT+CMGR=6"
    {
      more = true;
      while (more == true){
        //read one message from SIM
        STRRESET();
        Serial.flush();
        Serial.print("AT+CMGR=");        
        Serial.print(msgToRead);
        Serial.print(0x0D,BYTE);  //<cr>
        READFROMGSM();  
        // STR string will now contain a message such as
        // +CMGR:"REC UNREAD",0,"+19251234567","07/03/28,15:29:
        // 16+00"<cr><lf>TEXT<cr><lf>OK<cr><lf>OK<cr><lf>

        //doublecheck that "CMGR" indeed is the received message
        byteindex = STRFINDF("CMGR",0);
        if (byteindex >=0) {
          // found it - Unpack message in UNPACK in next loop cycle
          // SMSstart and SMSend are used in UNPACK
          // They point at start and end of useful message 
          loopState = Xunpack;   
          SMSstart = byteindex;  
          SMSend = STRix;  
          more = false;          // Break out of loop
        }
        else {
          // Did not find the message we asked for. This may mean
          // that the new message is in a >1 index, and that prior
          // index (e.g. #1) is empty. After such and attempt to
          // read non-existing message. GSM will return message
          // "<cr><lf>+CMS ERROR: 321<cr><lf>" 
          // If the message wasn't found, try next index in SIM. 
          // This is necessary because the message can be anywhere
          // within SIM although most often it will be in index #1
          msgToRead = msgToRead+1;
          if (msgToRead>msgMax){
            //Nothing valid found
            //Clear SIM, just to remove any random bad info
            STRRESET();
            Serial.flush();
            Serial.print("AT+CMGD=1,1");  // Delete ALL
            Serial.print(0x0D,BYTE);      //<cr>
            READFROMGSM();   // wait for 'OK' response from SIM

              // reset loop state - we will start over and wait
            // for new messages
            loopState = Xidle;
            lastRead = millis();
            more = false;
          }     
        }
      }
      break;
    }//end newmessage

  case Xerror:
    // Error was detected in a previos loop cycle. 
    // Clean up and start over.
    {
      //Delete the bad message 
      STRRESET();
      Serial.flush();
      Serial.print("AT+CMGD=");  
      Serial.print(msgToRead);   
      Serial.print(",0"); 
      Serial.print(0x0D,BYTE);  //<cr>
      READFROMGSM();
      loopState = Xidle;
      break;
    }

  default:
    //Other Xnnnnnnnnn state - no action
    {
      //
    }

  }//end switch
}//end receiving


/*
*********************************
 UNPACK
 Unpack message received from GSM
 Message is stored in string STR between 
 indices SMSstart and SMSend
 Index to message SIM is stored in msgToRead
 
 The information is processed only if loopState is Xunpack. 
 If so, read the details from STR and transition to new 
 loop state Xspecial (further processing in SPECIAL) or
 Xdisplayheader (further processing in LCDDISPLAY).  
 
 When we get to UNPACK, something has been received and is 
 available in STR string with format:
 <cr><lf>+CMGR: "REC UNREAD",0,"+19251234567","10/09/30,
 08:53:12+00"<cr><lf>TEXT<cr><lf><cr><lf>OK<cr><lf>
 If the actual text message  begins with @nnnn or #nnnn 
 (where "nnnn" is the correct PIN code for the device), 
 this means that we have received one of the special messages
 processed in SPECIAL function.
 
 Actual text is between first and second <cr><lf> ... {TEXT} in
 the above example.
 
 UNPACK uses and sets some global variables:
 o The message is in STR string
 o The CMGR message goes from index [SMSstart] to index [SMSend]
 */
void UNPACK(){
  int byteindex;         // used for checking what was received
  int startpoint;        // used for checking what was received
  int endpoint;          // used for checking what was received
  char inByte;           // for reading byte from STR
  char inByte2;          // for reading another byte from STR
  int numberIndex;       // used for checking what was received
  int timeInfo;          // used for checking what was received

  //---- Indices within received string
  int Pnumstart;         // points at phone number
  int Pnumend;

  //--- Phonebook info
  boolean samenumber;    // true if sender found in phonebook
  byte EEbyte;           // For EEPROM read/write 

    //--- other variables 
  String tempString = "";

  if (loopState == Xunpack)
  {//Something is received - unpack the details of the message
    //Look for start of message string, i.e. find 
    //<cr><lf> before actual message text
    for (int x=SMSstart; x<=SMSend;x++) { 
      if (STR[x] == 13 && STR[x+1] == 10){ //13=<cr>, 10=<lf>
        startpoint = x+2;
        break; // found the <cr><lf>, leave for loop
      }
    }

    //Look for end of message string, i.e.
    //find <cr><lf> after actual message
    for (int x=startpoint; x<=SMSend;x++) { 
      if (STR[x] == 13 && STR[x+1] == 10) { //13=<cr>, 10=<lf>
        endpoint = x-1;
        // New end point for STR string, nothing of 
        // interest after this index
        SMSend = x;              
        break;  // found the <cr><lf>, leave for loop
      }
    }

    //Extract the details from the SMS string and move those
    //substrings to individual other strings
    //     STR string contains a message from GSM
    //     [SMSstart] points at "CMGR"
    //     [SMSend] points at end characters
    //     In between is a complete SMS
    //     [startpoint] points at first byte of message text
    //     [endpoint] points at last byte of message text

    // find first '/' in between year and month numbers
    byteindex = STRINDEXOF('/', SMSstart);   
    if (byteindex == -1) {
      // did not find it ... assume there's nothing useful
      // in buffer. Setting 'Xerror' will erase incoming info,
      // and we start over waiting for messages 
      loopState = Xerror;  
    }
    else {
      // Found the '/' between day and month
      // "+12345678900","05/10/18,17:18:
      //                   ^ [byteindex] points here
      //Number (10 digits) is at byteindex-15 to byteindex-6 
      //Year is at byteindex-2 to byteindex-1
      //Month is at byteindex+1 to byteindex+2
      //Day is at byteindex+4 to byteindex+5
      //Time is at byteindex+7 to byteindex+11

      //Find phone number. 
      //numberIndex = byteindex - 10;
      //numberIndex points somewhere in the middle of number      
      //Look for delimiter '"' before sender's phone number
      for (int xx = numberIndex; xx>=0;xx--){
        if (STR[xx] == 0x22){
          Pnumstart = xx+1;    
          break;
        }
      }

      //Find delimiter '"' after sender's phone number
      for (int xx = numberIndex; xx<STRix;xx++){
        if (STR[xx] == 0x22){
          Pnumend = xx;        // points at first character after number
          break;
        }
      }

      //At this point, we start overwriting what may have
      //been stored in memory for any earlier message
      SMSnumber = STR.substring(Pnumstart,Pnumend); 

      //check if US format, which starts with "+1" and
      //is 12 characters long
      numberIndex = SMSnumber.indexOf("+1");
      if (numberIndex == 0 || SMSnumber.length() == 12){
        USformat = true;    
      }
      else {
        USformat = false;
      }

      //Date & time now. Convert to format "10 JUN, 2011 11:20AM"
      //Put Day at beginning of date & time string
      SMSdateTime = STR.substring(byteindex+4,byteindex+6);

      //Month added to date & time string
      inByte = STR[byteindex+1];           //'0' or '1'
      timeInfo = 10*(inByte-'0');  
      inByte = STR[byteindex+2];           // '0' - '9
      timeInfo = timeInfo+(inByte-'0')-1;  // 0-11 = Jan-Dec 
      tempString = monthNames[timeInfo]; 
      SMSdateTime.concat(" ");
      SMSdateTime.concat(tempString); //Month name     

      //Year added to date & time string
      tempString = " 20-- ";
      inByte = STR[byteindex-2];
      inByte2 = STR[byteindex-1];
      tempString[3] = inByte;
      tempString[4] = inByte2;
      SMSdateTime.concat(tempString);      

      //Time added to date & time string
      inByte = STR[byteindex+7];     

      timeInfo = 10*(inByte-'0');  
      inByte = STR[byteindex+8];         
      timeInfo = timeInfo+(inByte-'0');    // 0-23  

      if (timeInfo >12){
        timeInfo = timeInfo - 12;
        tempString = timeInfo + STR.substring(byteindex+9,byteindex+12) + "PM";
      }
      else if (timeInfo == 12) {
        tempString = STR.substring(byteindex+7,byteindex+12)+"PM";
      } 
      else {
        tempString = STR.substring(byteindex+7,byteindex+12)+"AM";
      }
      //Move hh:mm to string
      SMSdateTime.concat(tempString);  

      //Extract the actual text message
      SMSmessage = STR.substring(startpoint,endpoint+1);

      //Number checksum. For instance: if sender's number ends
      //with 3210, SMScsum = 32+10=42
      //The checksum is stored in SMScsum
      CALCULATECHECKSUM();  

      //Check if special messsage or regular text message
      //A special message is either
      //      @nnnn
      //or
      //      @nnnn NAME
      //where nnnn is a PIN code
      byteindex = SMSmessage.indexOf(correctPIN);
      if (byteindex == 1){
        if (SMSmessage[0] == '@'){
          // found '@' and the correct PIN in byte [1]-[4]
          // so this is a special message.
          // Handle the processing in SPECIAL
          loopState = Xspecial;    
          if (SMSmessage.length() >5){
            //There's more text in the message, after the pin code
            //That's sender's NAME --- so, set Name in phonebook
            SPmessage = SPname;
          }
          else {
            //Message is pin code only, so set main contact
            SPmessage = SPcontact;
          }
        }
      } 

      // Regular message
      else {
        loopState = Xdisplayheader; //message will be displayed 
        // But first, retrieve the 'name' from Phonebook, 
        // if available. Start by resetting Name info in RAM
        for (int y = 0; y< EnameLth; y++){
          PBname[y] = ' ';
        }
        //Look for senders name in phonebook
        if (USformat == true){
          for (int x = 0;x<EnamelistNbr;x++){
            if (checksumList[x] == SMScsum){
              //checksum matches, so check full 10-digit
              // number in PB against 12-digit incoming number
              samenumber = true; 
              byteindex = EnamesAt+EnamenbrLth*x; 
              // byteindex now points at number in phonebook
              for (int y=0;y<EnumberLth;y++){
                EEbyte = EEPROM.read(byteindex+y);
                //check all digits of number   
                samenumber = samenumber && (EEbyte == SMSnumber[y+2]);              
              }
              if (samenumber == true){ 
                // all digits of number matched, so retrieve NAME
                // name is in bytes stored right after NUMBER
                // within the Phonebook record
                byteindex = EnamesAt+EnamenbrLth*x+EnumberLth;
                for (int y = 0;y<EnameLth;y++){ 
                  EEbyte = EEPROM.read(byteindex+y);
                  PBname[y] = EEbyte;
                }       
                break;
              }             
            }
          }
        } 
      }

      //Entire message is now in RAM - Delete the message from SIM
      Serial.print("AT+CMGD=");  
      Serial.print(msgToRead); 
      Serial.print(",0"); 
      Serial.print(0x0D,BYTE);  //<cr>
      READFROMGSM();  // wait for 'ok' from GSM
    } 
  }//end if
}//end unpack


/*
*********************************
 SPECIAL
 
 EEPROM holds a basic phonebook.
 Here is the processing of messages for managing this phonebook
 When a message of this type is received, the caller's number is
 picked up and handled as described below. 
 
 (1)
 Message '@pin'
 i.e. the PIN and nothing more. This triggers Caller's number to
 be stored as the "main contact". When "CALL ME" button is pressed,
 the 'call me' message is sent to this number.
 
 (2)
 Message '@pin NAME'
 i.e. a Name included in the message from The Caller. Caller's
 number and the NAME are stored. Later, when a message is received
 from this number, NAME will be displayed
 */
void SPECIAL(){
  //---- Phonebook processing
  char firstfree;             // points at unused entry (10-39)
  String incomingInfo;        // for 'special' messages
  int byteindex;              // for parsing incoming message
  byte EEbyte;                // For EEPROM read/write 
  byte readByte;              // For reading from GSM 
  boolean wefoundit = false;  // true when info found
  byte sender;                // index in Phonebook (0 - 19)
  boolean samenumber;         // true if sender found in phonebook
  boolean replied;            // true when GSM has replied
  int incominglth;

  if (loopState == Xspecial && USformat == true){
    // We got here because message starts with "@pin"
    // These are only accepted if sender's number is US-formatted
    // If not US number format, ignore message 

      //Message accepted, send confirmation reply to sender
    replied = false;
    Serial.flush();
    Serial.print("AT+CMGS=");
    Serial.print(0x22,BYTE);  // "
    Serial.print(SMSnumber);  
    Serial.print(0x22,BYTE);  // "
    Serial.print(0x0D,BYTE);  // <cr>

    //Wait for response from GSM
    while (replied == false) {
      if(Serial.available() >0){
        readByte=Serial.read();
        if (readByte == '>'){
          //Send message
          Serial.print("Message Received");
          Serial.print(0x1A,BYTE);  //<ctrlZ>
          //Wait for 'OK'
          READFROMGSM(); 
          replied = true;
        }
      } 
    }

    if (SPmessage == SPname) {
      // Trim away everything except name string in the message
      byteindex = SMSmessage.indexOf(' ');
      incomingInfo = SMSmessage.substring(byteindex); 
      incomingInfo = incomingInfo.toUpperCase(); 
    }

    // Sets SMScsum = callernumber 10*[6] + [7] + 10*[8] + [9]  
    // That is, a number ending with 1234 gets checksum 12+34 = 46
    CALCULATECHECKSUM();   

    //Find caller in EEPROM phonebook memory
    //or find an empty place in the phonebook for the caller 
    //   List of name info starts at EEnames
    //   There are EEnamelistlength entries in the list
    //   Each entry is EEnameLength bytes
    //   Each entry is phonenr[10byte] & name[remainder bytes]
    //   Sender's number needs to be of US format
    wefoundit = false;
    firstfree = -1;
    //start looking
    for (int x = 0;x<EnamelistNbr;x++){
      //compare checksum
      if (checksumList[x] == SMScsum){
        //checksum fits, so check full 10-digit number
        samenumber = true; 
        byteindex = EnamesAt+EnamenbrLth*x;
        for (int y=0;y<EnumberLth;y++){
          EEbyte = EEPROM.read(byteindex+y);
          samenumber = samenumber && (EEbyte == SMSnumber[y+2]);
        }
        if (samenumber == true){
          //all digits match
          wefoundit = true;
          sender = x;   //sender's place in Phonebook
        }
      }
      else if (checksumList[x] == 0xFF) {
        if (firstfree == -1){
          firstfree = x;  //free position in list
        }
      }
      if (wefoundit == true){
        break;
      }
    }//end for

    // At this point, wefoundit is true if number listed in 
    // EEPROM already. In that case, 'sender' points at the
    // item in the list
    // if wefoundit is false, 'firstfree' points at an ununused
    // item in list
    // if firstfree is -1, there are no free items in namelist
    if (wefoundit == false && (firstfree !=-1)){
      sender = firstfree;
      wefoundit = true;
    }
    // 'sender' now points at where to store information, 
    // regardless of whether known before or not

    //update EEPROM accordning to message
    //if wefoundit is false at this point, EEPROM list 
    //was full and message is ignored
    if (wefoundit == true){   
      switch (SPmessage){
      case SPcontact:
        {
          EEPROM.write(EcontactAt,sender);
          CONTACTnumber = SMSnumber;
        }
      case SPname:
        {// four things to update: 
          //   1) checksum in memory
          //   2) checksum in EEPROM
          //   3) sender's number
          //   4) senders name if provided

          //1)
          EEPROM.write(EnamelistAt+sender, SMScsum);

          //2)
          checksumList[sender] = SMScsum;
          incominglth = incomingInfo.length();

          //3)
          byteindex = EnamesAt + EnamenbrLth*sender;
          for (int x = 0;x<EnumberLth;x++){
            EEPROM.write(byteindex+x,SMSnumber[x+2]);  //the number in 10-digit format ('+1' ignored)
          }

          //4)
          if (SPmessage == SPname){//not for 'contact' command
            byteindex = EnamesAt + EnamenbrLth*sender+EnumberLth;

            //name copied from message to EEPROM
            for (int x = 0;x<EnameLth;x++){
              if (x<incominglth){
                EEPROM.write(byteindex+x,incomingInfo[x]); 
              }
              else {
                EEPROM.write(byteindex+x,' ');
              }
            }
          }
        } 
      } 
    } // end of EEPROM update
    loopState = Xidle; 
    SMSnumber = "";  //erase message from internal memory  
  }
} //end SPECIAL


/*
*********************************
 LCDDISPLAY
 If( loopState == Xdisplayheader, the header of a newly
 received SMS shall be displayed [with BEEP]     
 If loopState == Xdisplaymessage, the rest of the SMS shall
 be displayed [no BEEP]
 */
void LCDDISPLAY() { 
  String displayString; // The string to write to LCD
  byte messageRow;      // Row number on LCD
  int fromIndex;        // Index within string for actual text
  int toIndex;      
  int SMSlth;           //length of message 
  boolean more;         // Used to break out of loops
  int lastSpace;        // Looking for ' ' in the word wrapping     

  if( loopState == Xdisplayheader || loopState == Xdisplaymessage) {
    // The SMS currently in RAM variables is to be displayed
    // No new SMS will show until previous is cleared
    // Display of "header" looks like this
    //  row1   From: [name if available]
    //  row2      (925)-123-4567
    //  row3   blank            
    //  row4   22 Oct 2010  11:08am          

    // After pressing 'clearl, actual message is displayed
    //  row1   message message message      [messagerow 1]
    //  row2   message message message
    //  ...
    //  row4  message message message       [messagerow 4]
    if (SMSnumber == ""){
      //nothing to display - go idle
      CLEARSCREEN();
      LCDnumber = "";
      loopState = Xidle;
    }
    else {
      switch (loopState){
      case Xdisplayheader:
        { // Display the message header
          // Start by clearing screen
          CLEARSCREEN();
          LIGHTSON();

          //Name from Phonebook
          SETROW(1);  
          lcd.print ("From: ");
          lcd.print(PBname);

          //Sender's phone number
          SETROW(2);
          if (SMSnumber.length()>0){

            if (USformat == true){
              displayString = "(" + SMSnumber.substring(2,5)+")"+ SMSnumber.substring(5,8)+"-"+SMSnumber.substring(8,12);
              LCDnumber = SMSnumber;
            }
            else {
              displayString = SMSnumber;
            }
            lcd.print(displayString);
          }

          //Date & Time
          SETROW(4);
          lcd.print(SMSdateTime);

          //Beep and turn on LED to indicate new message  
          BEEP(); 
          loopState = Xheaderonscreen;

          //Set up screen saver
          screensaveTime = millis()+timeoutmax;
          screenSaving = false;
          break; //end of header display
        }    
 
      case Xdisplaymessage:
        { // The actual message is displayed
          CLEARSCREEN();
          messageRow = 1;  // First row for message text
          fromIndex = 0;
          SMSlth = SMSmessage.length();
          more = true;

          // Word wrap      
          while (more == true) { 
            // where is next space?
            if (SMSlth - fromIndex > rowLength){ 
              //more than one row left
              toIndex = fromIndex+rowLength;
              lastSpace = FINDSPACE(fromIndex,toIndex);       
              SETROW(messageRow);
              displayString  = SMSmessage.substring(fromIndex,lastSpace);
              displayString  = displayString.toUpperCase();    
              lcd.print(displayString);
              messageRow = messageRow+1;
              fromIndex = lastSpace+1; 
              if (messageRow >= LCDrows){
                //nothing more is displayed
                //truncate rest of message
                loopState = Xsmsonscreen;
                more = false;
              }
            }
            else {
              //Last row
              SETROW(messageRow);
              lastSpace = min(SMSlth, fromIndex+rowLength);
              displayString  = SMSmessage.substring(fromIndex,lastSpace);
              displayString  = displayString.toUpperCase();    
              lcd.print(displayString);
              loopState = Xsmsonscreen;
              more = false;
            }
          }//end while
          break;
        } // end Xdisplaymessage
      }
    }
  }
}// end LCDDISPLAY


/*
*********************************
 BUTTONS
 Processing of button input
 Four buttons:
   >>  Send "call me" text message to predefined number
   >> Reply yes to the currently displayed message
   >> Reply no to the currently displayed message
   >> Clear the message currently displayed
 */
void BUTTONS()
{
  now = millis();
  whichButton = notPressed;
  boolean replied;
  byte readByte;

  if (digitalRead(CALLbutton) == LOW){
    //CALL ME processed here
    if (CONTACTnumber[0] == '-'){
      //If '-', contact is not defined, so no action
      LIGHTSON();
      SETROW(1);
      lcd.print("CONTACT PERSON");
      SETROW(2);
      lcd.print("NOT DEFINED");
      delay (3000);
      CLEARSCREEN();
    }
    else { //Process CALL ME input
      buttonTime = now;
      whichButton = CALLbutton;
      LIGHTSON();
      screenSaving=false;  
      screensaveTime = now+timeoutmax;

      //Indicate on LCD that sending is happening
      CLEARSCREEN();
      SETROW(2);
      lcd.print("SENDING");
      SETROW(3);
      lcd.print(" --- CALL ME ---");

      //Send via GSM, start with sending "CMGS" command
      replied = false;
      Serial.flush();
      Serial.print("AT+CMGS=");
      Serial.print(0x22,BYTE);  // "
      Serial.print(CONTACTnumber);  
      Serial.print(0x22,BYTE);  // "
      Serial.print(0x0D,BYTE);  // <cr>

      //Wait for reply
      while (replied == false) {
        if(Serial.available() >0){
          readByte=Serial.read();
          if (readByte == '>'){
            //Send message
            Serial.print("  --- Call Me ---");
            Serial.print(0x1A,BYTE);  //<ctrlZ>

            //Wait for 'OK' from GSM
            READFROMGSM(); 
            replied = true;
          }
        } 
      }
      //Sending completed
      SETROW(4);
      lcd.print("MESSAGE SENT");
      delay (3000);
    }//end processing of CALL

    //Return to what was previously displayed
    if (loopState == Xheaderonscreen) {
      loopState = Xdisplayheader;
    }
    else if (loopState == Xsmsonscreen){
      //Re-display the unread, i.e. unacknowledged, 
      //message that was on screen before
      loopState = Xdisplaymessage;
    }
    else {
      // Screen probavly cleared already, and status 
      // probably Xidle but let's set status and clear screen
      // anyway. Xidle triggers a look for new messages
      CLEARSCREEN();
      loopState = Xidle;
    }
  }

  //YES, NO, ACK & 'nothing' processed here 
  else { 
    if (now-buttonTime <= 500) {
      //Ignores pressings less than 0.5 sec apart  
    }
    else { // all remaining processing in this 'else' branch
      buttonTime = now;
      if (digitalRead(YESbutton) == LOW){
        whichButton = YESbutton;
      }  
      if (digitalRead(NObutton) == LOW){
        whichButton = NObutton;
      }  
      if (digitalRead(ACKbutton) == LOW){
        whichButton = ACKbutton;
      }   

      // If in screen saving state, any button just lights up
      // screen, nothing else
      if (screenSaving == true && whichButton != notPressed) {
        LIGHTSON();
        screenSaving = false;  // screen On but nothing else
        screensaveTime = now+timeoutmax;
      }
      else { 
        if (whichButton == notPressed) {
          // do nothing 
        }
        else { //all other button action within this 'else' branch
          // screensave timeout counts from now
          screensaveTime = now+timeoutmax; 
          switch (whichButton){
          case ACKbutton:
            {
              if (loopState == Xheaderonscreen) {
                //Header of a message is displayed
                //Switch to display of message text 
                digitalWrite(LEDpin, LOW);    //Turn off LED
                loopState = Xdisplaymessage;  //Show message
              }
              else if (loopState == Xsmsonscreen) {
                //Message text is on screen 
                //Clear LCD and allow new message to be received 
                CLEARSCREEN();
                loopState = Xidle;  // Done - wait for next message
              }    
              break;
            }//end ACK

          case NObutton: 
            {
            }
          case YESbutton:
            {
              //*******YES and NO buttons processed here
              //Ignore if no message is being displayed
              //at the moment
              if (loopState == Xsmsonscreen) {
                if (LCDnumber != "") {  
                  //Action only if valid sender's number 
                  //is available
                  CLEARSCREEN();
                  SETROW(3);

                  //Turn off LED
                  digitalWrite(LEDpin, LOW);  

                  // Send command
                  // AT+CMGS="+123456789000"<cr>TextText<ctrlZ>
                  replied = false;
                  Serial.flush();
                  Serial.print("AT+CMGS=");
                  Serial.print(0x22,BYTE);  // "
                  Serial.print(LCDnumber);  
                  Serial.print(0x22,BYTE);  // "
                  Serial.print(0x0D,BYTE);  // <cr>

                  // Wait for confirmation from GSM
                  while (replied == false) {
                    if(Serial.available() >0){
                      readByte=Serial.read();
                      if (readByte == '>'){

                        // GSM received the 'CMGS" and is ready
                        // for the message text
                        // Send message and update LCD
                        if (whichButton == NObutton){
                          lcd.print("SENDING --- NO ---");
                          Serial.print("  --- NO ---");
                        }
                        else {
                          lcd.print("SENDING -- YES/OK --");
                          Serial.print("  -- YES/OK --");
                        }
                        Serial.print(0x1A,BYTE);  //<ctrlZ>

                        // Wait for 'OK' from GSM
                        READFROMGSM(); 
                        replied = true;
                      }
                    } 
                  }

                  //Sending completed         
                  SETROW(4);
                  lcd.print("REPLY SENT");
                  delay (3000);
                  CLEARSCREEN();
                  loopState = Xidle; //ready for next message
                }
              }
            }
          }
        }    
      }
    }
  }
}


/*
*********************************
 BEEP
 Beep & LED indicates that a new message has been received
 */
void BEEP(){
  int beepsound[] = {
    Tone1, Tone1, Tone1, Tone2, Tone3, Tone4                           }; 

  //Turn on LED  - Stays on until message is read
  digitalWrite(LEDpin, HIGH);

  //Beep
  for (int x = 0; x<=6; x++){
    tone(BEEPERpin,beepsound[x],beepLength);
    delay (beepPause);
  }
}



/*
*********************************
 CLEARSCREEN
 Erases all text on LCD
 Screen backlightremains on
 */
void CLEARSCREEN(){
  lcd.clear();
}



/*
*********************************
 SCREENSAVE
 Turns LCD dark if timeout reached
 */
void SCREENSAVE(){
  if (screenSaving == false){
    now = millis();
    if (now > screensaveTime) {
      //Go Dark
      lcd.noDisplay();
      digitalWrite(LCDonoff,LOW);   //backlight off
      screenSaving = true;
    }
  }
}


/*
*********************************
 LIGHTSON
 Turns LCD on
 */
void LIGHTSON(){
  digitalWrite(LCDonoff,HIGH);  //backlight on
  lcd.display();
}


/*
*********************************
 SETROW
 Sets LCD row for text display
 top row is rownumber 1
 */
void SETROW(byte rownumber){
  rownumber = rownumber -1;
  lcd.setCursor(0,rownumber);
}


/*
*********************************
 READFROMGSM
 After sending an order to GSM, we expect a reply which
 could be either of...
     1) A reply string, followed by "OK"
 
     2) An error message (ends with 321)
 
     3) "OK" only, as acknowledge of a command to GSM 
 
 Process remains here until one of these is received
 No timeout or similar here - could be improved
 */

void READFROMGSM(){
  char inByte;     // for reading one byte from GSM
  char OKstring[] = {
    0x0D,0x0A,'O','K',0x0D,0x0A                                        };
  char ERRstring[] = {
    ' ','3','2','1',0x0D,0x0A                                      };
  int Rindex;
  boolean ENDfound = false; // true when string found

  //process stays here until "OK" is received
  while (ENDfound == false) {
    if(Serial.available() >0)
    {
      inByte=Serial.read();    //Get character from serial port
      STRADD(inByte);

      if (inByte == 0x0A) {
        Rindex = STRix;
        
        //Need to break out of loop if OKstring 
        //or ERRstring was received
        if (Rindex >=19){
          if (ERRstring[5] == inByte){
            if (ERRstring[4] == STR[Rindex-2]){
              if (ERRstring[3] == STR[Rindex-3]){
                if (ERRstring[2] == STR[Rindex-4]){
                  if (ERRstring[1] == STR[Rindex-5]){
                    if (ERRstring[0] == STR[Rindex-6]){
                      ENDfound = true;
                    } 
                  } 
                } 
              } 
            } 
          }
        }
        if (Rindex >=5){
          if (OKstring[5] == inByte){
            if (OKstring[4] == STR[Rindex-2]){
              if (OKstring[3] == STR[Rindex-3]){
                if (OKstring[2] == STR[Rindex-4]){
                  if (OKstring[1] == STR[Rindex-5]){
                    if (OKstring[0] == STR[Rindex-6]){
                      ENDfound = true;
                    } 
                  } 
                } 
              } 
            } 
          }
        }
      }
    }
  }
}


/*
*********************************
 CALCULATECHECKSUM
 If name defined (i.e. who is calling from this number), sort of
 a checksum of last 4 digits in the phone number (in decimal
 form, 00-99) is used for quicker indexing in "phone book" stored
 in EEPROM.  For example, xxx4567 becomes 45+67 = 112.
 Checksum is 0 for number xxx0000 up to 198 for number xxx9999 
 This is the first search criteria when receiving a message
 If name not defined, byte in EEPROM Phonebook is 0xFF
 
 The result of the checksum calculation is 
 stored in SMScsum variable.
 */
void CALCULATECHECKSUM(){
  char csumdigit;
  int digitvalue;
  int CSresult = 0;
  int nbrlength = SMSnumber.length()-1;
  int ix;

  for (int x = 3;x>=0;x--){
    ix = nbrlength - x;
    if (ix>=0) {
      csumdigit = SMSnumber[ix];
      digitvalue = csumdigit - '0';
      if (x==3 || x==1){
        digitvalue = digitvalue*10;
      }
      CSresult = CSresult + digitvalue;  
    }  
  }
  SMScsum = CSresult;
}



/*
*********************************
 STRRESET
 Reset STR string
 */
void STRRESET(){
  STRix = 0;
}


/*
*********************************
 STRADD
 Add character to STR
 */
void STRADD(char inchar){
  if (STRix < STRlengthmax) {
    STR[STRix] = inchar;
    STRix++;
  }
  else if (STRix == STRlengthmax){
    //Do not fill STR beyond STRlengthmax - truncate message by
    //inserting EOM indication. Note that insertion of 'OK' may
    // be incorrect if the byte stream from GSM isn't a real
    // SMS but some form of error message - this is not handled
    // in this version, but that's okay
    STR[STRix] = 0x0D;   //cr
    STR[STRix+1] = 0x0A; //lf
    STR[STRix+2] = 0x0D; //cr
    STR[STRix+3] = 0x0A; //lf
    STR[STRix+4] = 'O';  //cr
    STR[STRix+5] = 'K';  //lf
    STR[STRix+6] = 0x0D; //cr
    STR[STRix+7] = 0x0A; //lf
    STRix = STRix+8;
  }
  else {
    //do nothing if index > maxlength, i.e. we have done the
    //EOM inseertion and are just emptying out the serial
    //communication link, i.e. waiting for the GSM to finish
    //its transmittion of (ignored) characters  
  }
}


/*
*********************************
 STRFINDB
 Find substring within STR
 Search from end of string towards front
 */
int STRFINDB (String instring){
  int inlast = instring.length()-1;  //last byte of instring
  char lastbyte = instring[inlast];  //the actual byte
  boolean foundstring = false;       //true if string found
  int compareindex;                  //index within instring
  int result = -1;                   //returned value

  for (int ix = STRix-1;ix >=0;ix--){
    if (foundstring == false){
      //not found yet - keep looking
      if (STR[ix] == lastbyte) {
        //found matching byte
        foundstring  = true;
        compareindex = inlast;
      }
    }
    else {
      //found some matching bytes  - is the rest matching too?
      compareindex--;
      if (STR[ix] == instring[compareindex]){
        //still good
        if (compareindex == 0){
          //found the whole string - stop looking
          result = ix;   //points at first byte of found string  
          break;
        }
      }
      else {
        //false alarm = string not found, keep looking
        foundstring = false;
      }
    }
  }
  return result;
}


/*
*********************************
 STRFINDF
 Find substring within STR
 Search from front, starting at [startpoint]
 */
int STRFINDF (String instring, int startpoint){
  int inlast = instring.length()-2;  //last byte of instring
  char firstbyte = instring[0];      //first byte
  boolean foundstring = false;       //true if string found
  int compareindex;                  //index within instring
  int returnindex;                   //index to be returned
  int result = -1;                   //returned value

  for (int ix = startpoint;ix <STRix;ix++){
    if (foundstring == false){
      //not found yet - keep looking
      if (STR[ix] == firstbyte) {
        //found equal byte
        foundstring  = true;
        returnindex = ix;
        compareindex = 0;
      }
    }
    else {
      //found some matching bytes  - is the rest matching too?
      compareindex++;
      if (STR[ix] == instring[compareindex]){
        //still good
        if (compareindex == inlast){
          //found the whole string - stop looking
          result = returnindex;
          break;
        }
      }
      else {
        //false alarm = string not found, keep looking
        foundstring = false;
      }
    }
  }
  return result;
}


/*
*********************************
 STRINDEXOF
 Find a character within STR string
 Seartch starts at [startpoint]
 Returns -1 if not found
 */
int STRINDEXOF (char inchar, int startpoint)
{
  int result = -1;
  for (int ix = startpoint;ix <STRix;ix++){
    if (STR[ix] == inchar) {
      result = ix;
      break;
    }
  }
  return result;
}


/*
*********************************
 FINDSPACE
 Looks for ' ' within SMSmessage string
 Search goes from [fromix] to [toix]
 Returns -1 if not found
 */
int FINDSPACE (int fromix, int toix){
  boolean spacefound = false;
  int ix = toix;
  while (spacefound == false){
    if (SMSmessage[ix] == ' '){
      spacefound = true;
    }
    else {
      ix = ix-1;
      if (ix == fromix){
        spacefound = true;
        ix = toix;
      }
    }
  }
  return ix;
}
