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
#include <EEPROM.h>
#include "remoconRoboLib.h"

union{
	byte byteVal[4];
	float floatVal;
}val;

union{
	byte byteVal[2];
	short shortVal;
}valShort;

const int analogs[8] PROGMEM = {A0,A1,A2,A3,A4,A5,A6,A7};
String mVersion = "06.01.106";

#define TYPE_GET		1
#define TYPE_RUN		2
#define TYPE_RESET		4
#define TYPE_START		5

#define CMD_VERSION		0
#define CMD_ROBOT		5
#define CMD_MOTOR		10
#define CMD_CHECKREMOTE	14
#define CMD_GETREMOTE	18
#define CMD_DIGITAL		30
#define CMD_ANALOG		31
#define CMD_PWM			32
#define CMD_SERVO		33
#define CMD_TONE		34

static Servo servos[8];
static int servo_pins[8]={0,0,0,0,0,0,0,0};

void setup()
{
	remoconRobo_init();

	digitalWrite(13, HIGH);
	delay(300);
	digitalWrite(13, LOW);

	Serial.begin(115200);
	delay(500);

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

/*
ff 55 len idx action device port slot data a
0  1  2   3   4      5      6    7    8
*/
static void parseData()
{
	int device = buffer[5];
	switch(buffer[4]){
		case TYPE_GET:
			Serial.write(0xff);
			Serial.write(0x55);
			Serial.write(buffer[3]);
			readSensor(device);
			Serial.println();
			break;
		case TYPE_RUN:
			runModule(device);
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

static void callOK()
{
	Serial.write(0xff);
	Serial.write(0x55);
	Serial.println();
}

//1 byte 2 float 3 short 4 len+string 5 double
static void sendByte(char c)
{
	Serial.write(1);
	Serial.write(c);
}

static void sendFloat(float value)
{
	Serial.write(2);
	val.floatVal = value;
	Serial.write(val.byteVal[0]);
	Serial.write(val.byteVal[1]);
	Serial.write(val.byteVal[2]);
	Serial.write(val.byteVal[3]);
}

static void sendShort(double value)
{
	Serial.write(3);
	valShort.shortVal = value;
	Serial.write(valShort.byteVal[0]);
	Serial.write(valShort.byteVal[1]);
}

static void sendString(String s)
{
	int l = s.length();
	Serial.write(4);
	Serial.write(l);
	for(int i=0;i<l;i++) {
		Serial.write(s.charAt(i));
	}
}

static short readShort(int idx)
{
	valShort.byteVal[0] = buffer[idx+0];
	valShort.byteVal[1] = buffer[idx+1];
	return valShort.shortVal; 
}

static void runModule(int device)
{
	//0xff 0x55 0x6 0x0 0x2 0x22 0x9 0x0 0x0 0xa 
	int pin = buffer[6];
	switch(device){
		case CMD_MOTOR:
			remoconRobo_setMotor(pin-1, readShort(7));
			break;
		case CMD_ROBOT:
			remoconRobo_setRobot(pin, buffer[7]);
			break;
		case CMD_DIGITAL:
			pinMode(pin, OUTPUT);
			digitalWrite(pin, buffer[7]);
			break;
/*
		case CMD_PWM:
			pinMode(pin, OUTPUT);
			analogWrite(pin, buffer[7]);
			break;
*/
		case CMD_TONE:
			remoconRobo_tone(readShort(6), readShort(8));
			break;
		case CMD_SERVO: {
			int v = buffer[7];
			Servo sv = servos[searchServoPin(pin)]; 
			if(v >= 0 && v <= 180) {
				if(!sv.attached()) {
					sv.attach(pin);
				}
				sv.write(v);
			}
			break;
		}
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

static void readSensor(int device)
{
	/**************************************************
	ff    55      len idx action device port slot data a
	0     1       2   3   4      5      6    7    8
	0xff  0x55   0x4 0x3 0x1    0x1    0x1  0xa 
	***************************************************/
	int pin = buffer[6];
	switch(device){
		case CMD_CHECKREMOTE:
			sendByte(remoconRobo_checkRemote(pin));
			break;
		case CMD_GETREMOTE:
			sendByte(remoconRobo_getRemote());
			break;
		case CMD_VERSION:
			sendString(mVersion);
			break;
		case CMD_DIGITAL:
			pinMode(pin, INPUT);
			sendByte(digitalRead(pin));
			break;
		case CMD_ANALOG:
			pin = pgm_read_byte(&analogs[pin]);
			pinMode(pin, INPUT);
			sendFloat(analogRead(pin));
			break;
	}
}
