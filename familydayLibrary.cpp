#include <stdint.h>
#include <Arduino.h>
#include <avr/interrupt.h>
#include <avr/io.h>
#include <EEPROM.h>

#include "familydayLibrary.h"

#define MATCH(ticks, desired_us) \
	 ( ticks >= (desired_us) - ((desired_us)>>2)-1 \
	&& ticks <= (desired_us) + ((desired_us)>>2)+1)

#define DUR_H_HDR	9000
#define DUR_L_HDR	4500
#define DUR_L_RPT	2250
#define DUR_H_BIT	 560
#define DUR_L_BIT1	1690
#define DUR_L_BIT0	 560
//#define NEC_RPT_PERIOD	110000
#define DUR_L_TIMEOUT	(110*1000UL)

#define TONE_PORT	8

struct MotorPort {
	uint8_t pwm;
	uint8_t dir;
} static const MotorPort[3] = {
	{5,  4},		// R
	{6,  7},		// L
	{11, 12},		// C
};

enum {
	CH_R,
	CH_L,
	CH_C,
};

enum {
	STATE_L_IDLE,
	STATE_H_HDR,
	STATE_L_HDR,
	STATE_H_BIT,
	STATE_L_BIT,
	STATE_H_STOP,
};
static volatile uint8_t state;
static volatile uint8_t rawCount;
static volatile uint32_t rawData;

static volatile uint32_t validData;
static volatile uint8_t updated;

static volatile uint32_t last_timer;
static volatile int8_t calib;
#define EEPROM_CALIB	0x00

/*
uint32_t debug[100];
uint8_t debug2[100];
int debugCnt = 0;
*/
static void irq_int0(void)
{
	uint8_t irdata = digitalRead(2) ^ 1;
	uint32_t cur_timer = micros();
	uint16_t diff;
	if(cur_timer - last_timer >= 0x10000UL) {
		diff = 0xFFFF;
	} else {
		diff = cur_timer - last_timer;
	}
	last_timer = cur_timer;

//	debug[debugCnt] = diff;
//	debug2[debugCnt++] = (state<<4)|irdata;
	switch(state) {
	case STATE_L_IDLE:
	case STATE_L_HDR:
	case STATE_L_BIT:
		if(irdata == 0) {
			state = STATE_L_IDLE;
		//	validData = 0;
			return;
		}
		break;
	case STATE_H_HDR:
	case STATE_H_BIT:
	case STATE_H_STOP:
		if(irdata == 1) {
			state = STATE_H_STOP;
		//	validData = 0;
			return;
		}
		break;
	}

	switch(state) {
	case STATE_L_IDLE:	// L_IDLE -> H_HDR
		state = STATE_H_HDR;
		break;
	case STATE_H_HDR:	// H_HDR -> L_HDR
		if(MATCH(diff, DUR_H_HDR)) {
			state = STATE_L_HDR;
		} else {
			state = STATE_L_IDLE;
		//	validData = 0;
		}
		break;
	case STATE_L_HDR:	// L_HDR -> H_BIT,L_RPT(H_STOP)
		if(MATCH(diff, DUR_L_HDR)) {
			rawData = 0;
			rawCount = 0;
			state = STATE_H_BIT;
		} else if(MATCH(diff, DUR_L_RPT)) {
			state = STATE_H_STOP;
		} else {
			state = STATE_H_STOP;
		//	validData = 0;
		}
		break;
	case STATE_H_BIT:	// H_BIT -> L_BIT,L_IDLE
		if(MATCH(diff, DUR_H_BIT)) {
			if(rawCount >= 32) {
				if((((rawData>>8)^rawData) & 0x00FF00FF) == 0x00FF00FF) {
					validData = rawData & 0x00FF00FF;
					updated = 1;
				//	debug[debugCnt++] = validData;
				}
				state = STATE_L_IDLE;
			} else {
				state = STATE_L_BIT;
			}
		} else {
			state = STATE_L_IDLE;
		//	validData = 0;
		}
		break;
	case STATE_L_BIT:	// L_BIT -> H_BIT
		state = STATE_H_BIT;
		rawData = (rawData>>1);
		rawCount++;
		if(MATCH(diff, DUR_L_BIT1)) {
			rawData |= 0x80000000UL;
		} else if(MATCH(diff, DUR_L_BIT0)) {
			;
		} else {
			state = STATE_H_STOP;
		//	validData = 0;
		}
		break;
	case STATE_H_STOP:	// H_STOP -> L_IDLE
		state = STATE_L_IDLE;
		break;
	}
}

void familyday_initRemote(void)
{
	pinMode(2,INPUT);
	attachInterrupt(0, irq_int0, CHANGE);

	state = STATE_L_IDLE;
	validData = 0;
	updated = 0;
}

int familyday_getRemote(void)
{
	if(validData) {
		if(state == STATE_L_IDLE
		&& (micros() - last_timer) >= DUR_L_TIMEOUT) {
			validData = 0;
			updated = 1;
		}
	}
	return (validData>>16)&0xFF;
}

int familyday_getRemoteUpdated(void)
{
	int key = familyday_getRemote();
	int flag = updated;
	updated = 0;
	return (flag<<8)|key;
}

int familyday_checkRemote(int key)
{
	if(key == 0xFF)
		return familyday_getRemote() != 0;
	else
		return familyday_getRemote() == key;
}

void familyday_tone(int sound, int ms)
{
	int TCCR2Alast = TCCR2A;
	int TCCR2Blast = TCCR2B;
	int OCR2Alast = OCR2A;
	tone(TONE_PORT, sound, ms); delay(ms);
	TCCR2A = TCCR2Alast;
	TCCR2B = TCCR2Blast;
	OCR2A = OCR2Alast;
}

void familyday_init(void)
{
	int ch;
	for(ch = 0; ch < 3; ch++)
		pinMode(MotorPort[ch].dir, OUTPUT);

	pinMode(TONE_PORT, OUTPUT);
	pinMode(13, OUTPUT);

	TCCR0A=0x03; TCCR0B=0x03;	// timer0:8bit高速PWM, 1/64(977Hz), PWM6,5/timer
	TCCR1A=0x01; TCCR1B=0x0B;	// timer1:8bit高速PWM, 1/64(977Hz), PWM9,10/servo
	TCCR2A=0x03; TCCR2B=0x04;	// timer2:8bit高速PWM, 1/64(977Hz), PWM11,3/buzzer

	familyday_initRemote();
	calib = EEPROM.read(EEPROM_CALIB);

//	Serial.begin(9600);
}

int familyday_getCalib(void)
{
	return calib;
}

int familyday_calibRight(void)
{
	if(calib >= 127) {
		calib = 127;
		return -1;
	}
	calib++;
	EEPROM.update(EEPROM_CALIB, calib & 0xFF);
	return 0;
}

int familyday_calibLeft(void)
{
	if(calib <= -128) {
		calib = -128;
		return -1;
	}
	calib--;
	EEPROM.update(EEPROM_CALIB, calib & 0xFF);
	return 0;
}

void familyday_setMotor(int ch, int speed)
{
	if(speed > 255)  speed = 255;
	if(speed < -255) speed = -255;
	if(speed >= 0) {
		digitalWrite(MotorPort[ch].dir, HIGH);
		analogWrite(MotorPort[ch].pwm, speed);
	} else {
		digitalWrite(MotorPort[ch].dir, LOW);
		analogWrite(MotorPort[ch].pwm, -speed);
	}
}

void familyday_setRobot(int direction, int speed)
{
	int speedL = speed;
	int speedR = speed;
	if(calib >= 0) {
		speedR -= (calib * speed) >> 8;
	} else {
		speedL -= (-calib * speed) >> 8;
	}

	switch(direction) {
		case DIR_FORWARD:
			familyday_setMotor(CH_R,  speedR);
			familyday_setMotor(CH_L, -speedL);
			break;
		case DIR_LEFT:
			familyday_setMotor(CH_R,  speedR);
			familyday_setMotor(CH_L, 0);
			break;
		case DIR_RIGHT:
			familyday_setMotor(CH_R, 0);
			familyday_setMotor(CH_L, -speedL);
			break;
		case DIR_BACK:
			familyday_setMotor(CH_R, -speedR);
			familyday_setMotor(CH_L,  speedL);
			break;
		case DIR_ROLL_LEFT:
			familyday_setMotor(CH_R,  speedR);
			familyday_setMotor(CH_L,  speedL);
			break;
		case DIR_ROLL_RIGHT:
			familyday_setMotor(CH_R, -speedR);
			familyday_setMotor(CH_L, -speedL);
			break;
		default:
			break;
	}
}
