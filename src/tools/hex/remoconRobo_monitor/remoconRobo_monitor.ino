/*************************************************************************
* File Name          : remoconRobo_firmware.ino
* Author             : Ander, Mark Yan
* Updated            : Ander, Mark Yan
* Version            : V06.01.106
* Date               : 07/06/2016
* Description        : Firmware for Makeblock Electronic modules with Scratch.  
* License            : CC-BY-SA 3.0
* Copyright (C) 2013 - 2016 Maker Works Technology Co., Ltd. All right reserved.
* http://www.makeblock.cc/
**************************************************************************/
// copyright to SohtaMei 2019.
#include <Wire.h>
#include <Servo.h>
#include <EEPROM.h>		// for build error
#include "remoconRoboLib.h"

union {
	byte byteVal[4];
	float floatVal;
} val;

union {
	byte byteVal[2];
	short shortVal;
} valShort;

String mVersion = "06.01.106";

enum {
	TYPE_GET		= 1,
	TYPE_RUN		= 2,
	TYPE_RESET		= 4,
	TYPE_START		= 5,
};

enum {
	// get, run
	CMD_DIGITAL		= 30,

	// get
	CMD_VERSION		= 0,
	CMD_ISREMOTE	= 14,	// dummy
	CMD_CHECKREMOTEKEY	= 18,
	CMD_ANALOG		= 31,
	CMD_GETCALIB	= 37,

	// run
	CMD_ROBOT		= 5,
	CMD_MOTOR		= 10,
//	CMD_PWM			= 32,
	CMD_SERVO		= 33,
	CMD_TONE		= 34,
	CMD_PLAYMP3		= 35,
	CMD_STOPMP3		= 36,
	CMD_SETCALIB	= 38,
	CMD_INCCALIB	= 39,
};

enum {
	RSP_BYTE	= 1,
	RSP_FLOAT	= 2,
	RSP_SHORT	= 3,
	RSP_STRING	= 4,
//	RSP_DOUBLE	= 5,
//	RSP_LONG	= 6,
	RSP_REMOTE	= 7,
};

static Servo servos[8];
static int servo_pins[8]={0,0,0,0,0,0,0,0};

void setup()
{
	remoconRobo_init();

	digitalWrite(13, HIGH);
	Serial.begin(115200);
	delay(500);
	digitalWrite(13, LOW);

	remoconRobo_tone(500, 50); 
	Serial.print("Version: ");
	Serial.println(mVersion);
}

static byte prevc = 0;
static byte buffer[52];
static byte index = 0;
static byte dataLen;
static boolean isStart = false;

void loop()
{
	if(Serial.available()>0){
		byte c = Serial.read() & 0xff;
		if(c==0x55&&isStart==false){
			if(prevc==0xff){
				index=1;
				isStart = true;
			}
		}else{
			prevc = c;
			if(isStart){
				if(index==2){
				 dataLen = c; 
				}else if(index>2){
					dataLen--;
				}
				buffer[index] = c;
			}
		}
		index++;
		if(index>51){
			index=0; 
			isStart=false;
		}
		if(isStart && dataLen==0 && index>3){ 
			isStart = false;
			parseData(); 
			index=0;
		}
	}
}

/*------------------
	0 - ff
	1 - 55
	2 - len
	3 - idx(0)
	4 - type(1-get, 2-run, 4-reset, 5-start)
	5 - cmd
	6~- data
------------------*/
static void parseData()
{
	switch(buffer[4]){
	case TYPE_GET:
		readSensor(buffer[3], buffer[5]);
		break;
	case TYPE_RUN:
		runModule(buffer[5]);
		callOK();
		break;
	case TYPE_RESET:
		remoconRobo_init();
		callOK();
		break;
	case TYPE_START:
		callOK();
		break;
	}
}

/*------------------
	0 - ff
	1 - 55
	2 - 0d
	3 - 0a
------------------*/
static void callOK()
{
	Serial.write(0xff);
	Serial.write(0x55);
	Serial.println();
}

static short readShort(int idx)
{
	valShort.byteVal[0] = buffer[idx+0];
	valShort.byteVal[1] = buffer[idx+1];
	return valShort.shortVal; 
}

static char mp3initialized = 0;
static void runModule(int cmd)
{
	int buf6 = buffer[6];
	switch(cmd){
	case CMD_ROBOT:		// dir, speed
		remoconRobo_setRobot(buf6, buffer[7]);
		break;
	case CMD_MOTOR:		// port, speed[2]
		remoconRobo_setMotor(buf6-1, readShort(7));
		break;
	case CMD_DIGITAL:	// buf6, level
		pinMode(buf6, OUTPUT);
		digitalWrite(buf6, buffer[7]);
		break;
/*
	case CMD_PWM:
		pinMode(buf6, OUTPUT);
		analogWrite(buf6, buffer[7]);
		break;
*/
	case CMD_SERVO: {	// buf6, angle
		int v = buffer[7];
		Servo sv = servos[searchServoPin(buf6)]; 
		if(v >= 0 && v <= 180) {
			if(!sv.attached()) {
				sv.attach(buf6);
			}
			sv.write(v);
		}
		break;
	  }
	case CMD_TONE:		// tone[2], beat[2]
		remoconRobo_tone(readShort(6), readShort(8));
		break;
	case CMD_PLAYMP3:	// track, loop
		if(!mp3initialized) {
			remoconRobo_initMP3(30);
			mp3initialized = 1;
		}
		remoconRobo_playMP3(buf6, buffer[7]);
		break;
	case CMD_STOPMP3:
		remoconRobo_stopMP3();
		break;
	case CMD_SETCALIB:
		remoconRobo_setCalib(readShort(6));
		break;
	case CMD_INCCALIB:
		remoconRobo_incCalib(readShort(6));
		break;
	}
}

static int searchServoPin(int pin)
{
	for(int i=0; i<8; i++){
		if(servo_pins[i] == pin){
			return i;
		}
		if(servo_pins[i]==0){
			servo_pins[i] = pin;
			return i;
		}
	}
	return 0;
}

static void sendByte(char c)
{
	Serial.write(RSP_BYTE);
	Serial.write(c);
}

static void sendFloat(float value)
{
	val.floatVal = value;

	Serial.write(RSP_FLOAT);
	Serial.write(val.byteVal[0]);
	Serial.write(val.byteVal[1]);
	Serial.write(val.byteVal[2]);
	Serial.write(val.byteVal[3]);
}

static void sendShort(double value)
{
	valShort.shortVal = value;

	Serial.write(RSP_SHORT);
	Serial.write(valShort.byteVal[0]);
	Serial.write(valShort.byteVal[1]);
}

static void sendString(String s)
{
	int l = s.length();
	Serial.write(RSP_STRING);
	Serial.write(l);
	for(int i=0;i<l;i++) {
		Serial.write(s.charAt(i));
	}
}

static void sendRemote(void)
{
	Serial.write(RSP_REMOTE);
	Serial.write(remoconRobo_checkRemoteKey());
	valShort.shortVal = remoconRobo_getRemoteX();
	Serial.write(valShort.byteVal[0]);
	Serial.write(valShort.byteVal[1]);
	valShort.shortVal = remoconRobo_getRemoteY();
	Serial.write(valShort.byteVal[0]);
	Serial.write(valShort.byteVal[1]);
}

/*------------------
	0 - ff
	1 - 55
	2 - 0d
	3 - 0a
------------------*/
static void readSensor(int idx, int cmd)
{
	Serial.write(0xff);
	Serial.write(0x55);
	Serial.write(idx);

	int buf6 = buffer[6];
	switch(cmd){
	case CMD_VERSION:
		sendString(mVersion);
		break;
	case CMD_ISREMOTE:
		sendByte(remoconRobo_isRemoteKey(buf6));
		break;
	case CMD_CHECKREMOTEKEY:
	//	sendByte(remoconRobo_checkRemoteKey());
		sendRemote();
		break;
	case CMD_DIGITAL:
		pinMode(buf6, INPUT);
		sendByte(digitalRead(buf6));
		break;
	case CMD_ANALOG:
		buf6 = A0+buf6;
		pinMode(buf6, INPUT);
		sendFloat(analogRead(buf6));
		break;
	case CMD_GETCALIB:
		sendShort(remoconRobo_getCalib());
		break;
	}
	Serial.println();
}
