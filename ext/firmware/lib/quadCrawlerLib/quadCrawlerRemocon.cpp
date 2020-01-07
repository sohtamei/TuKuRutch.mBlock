// copyright to SohtaMei 2019.

#include <stdint.h>
#include <Arduino.h>
#include <avr/interrupt.h>
#include <avr/io.h>
#include <EEPROM.h>

#include "quadCrawlerRemocon.h"

#define PORT_IR_RX	2		// INT0
#define PORT_LED	13

enum {
	STATE_H_IDLE,

	// digital
	STATE_L_HDR,
	STATE_H_HDR,
	STATE_L_BIT,
	STATE_H_BIT,
	STATE_L_STOP,

	// analog
	STATE_ANALOG_DATA,
};
static volatile uint8_t state;
static volatile uint8_t rawCount;
static volatile uint32_t rawData;

static volatile uint32_t last_timer;
static volatile uint32_t last_timer2 = 0;
static volatile uint32_t last_timer3 = 0;

static struct remoconData remoconData1;
static struct remoconData remoconData2;
static int updated = 0;


// nec remote --------------------------------------------------

#define MATCH(ticks, desired_us) \
	 ( ticks >= (desired_us) - ((desired_us)>>2)-1 \
	&& ticks <= (desired_us) + ((desired_us)>>2)+1)

#define DUR_T2		562
#define DUR_L_HDR	(DUR_T2*16)
#define DUR_H_HDR	(DUR_T2*8)
#define DUR_H_RPT	(DUR_T2*4)
#define DUR_L_BIT	(DUR_T2*1)
#define DUR_H_BIT1	(DUR_T2*3)
#define DUR_H_BIT0	(DUR_T2*1)
#define DUR_H_TIMEOUT	300UL	//110UL	// ms	remote error by colorWipe

// analog remote ------------------------------------------------

#define MATCH2(ticks, desired_us) \
	 ( ticks >= (desired_us) - (DUR_T/2) \
	&& ticks <= (desired_us) + (DUR_T/2))

#define DUR_T			350
#define DUR_H_TIMEOUT_A	300UL	// ms

#define Y_CENTER		16
#define X_CENTER		16
#define BIT_SIZE		15

union analogRemote {
	uint16_t data;
	struct {
		unsigned int keys		: 3;	// bit2~0  :
		unsigned int x			: 5;	// bit7~3  :
		unsigned int y			: 5;	// bit12~8 :
		unsigned int ch			: 2;	// bit14~13: (1)chA, (2)chB, (0)chC
	} b;
};

static volatile uint8_t analog_ch = 0;

// REMOTE -------

static void irq_int0(void)
{
	uint8_t irdata = digitalRead(PORT_IR_RX);
	uint32_t cur_timer = micros();
	uint16_t diff;// = ((cur_timer - last_timer) & ~0x80000000);
	if(cur_timer - last_timer >= 0x10000UL) {
		diff = 0xFFFF;
	} else {
		diff = cur_timer - last_timer;
	}
	last_timer = cur_timer;

//	debug[debugCnt] = diff;
//	debug2[debugCnt++] = (state<<4)|irdata;
	switch(state) {
	case STATE_H_IDLE:
	case STATE_H_HDR:
	case STATE_H_BIT:
		if(irdata == 1) {
			state = STATE_H_IDLE;
			return;
		}
		break;

	case STATE_L_HDR:
	case STATE_L_BIT:
	case STATE_L_STOP:
		if(irdata == 0) {
			state = STATE_L_STOP;
			return;
		}
		break;

	case STATE_ANALOG_DATA: {
		if(MATCH2(diff, DUR_T)) {
			if(!(rawCount&1))
				rawData = (rawData<<1) | 1;
			rawCount += 1;
		} else if(MATCH2(diff, DUR_T*2)) {
			rawData = (rawData<<1) | 0;
			rawCount += 2;
		} else {
			if(irdata == 0)
				state = STATE_L_HDR;
			else
				state = STATE_H_IDLE;
			return;
		}
		if(rawCount >= BIT_SIZE*2) {
			state = STATE_H_IDLE;
			union analogRemote rData;
			rData.data = rawData;
			if(!analog_ch) {
				analog_ch = rData.b.ch;
			} else if(rData.b.ch == analog_ch) {
				memset(&remoconData1, 0, sizeof(remoconData1));
				remoconData1.keys	= rData.b.keys + BUTTON_A_XY;
				remoconData1.x		= (rData.b.x - X_CENTER)*16;
				remoconData1.y		= (rData.b.y - Y_CENTER)*16;
				last_timer2 = millis();
				updated = REMOTE_ANALOG;
				digitalWrite(PORT_LED, 1);
			}
		}
		return;
	  }
	}

	switch(state) {
	case STATE_H_IDLE:	// H_IDLE -> L_HDR
		state = STATE_L_HDR;
		break;
	case STATE_L_HDR:	// L_HDR -> H_HDR
		if(MATCH(diff, DUR_L_HDR)) {
			state = STATE_H_HDR;
		} else if(MATCH2(diff, DUR_T*3)) {
			state = STATE_ANALOG_DATA;
			rawData = 0;
			rawCount = 0;
		} else {
			state = STATE_H_IDLE;
		}
		break;
	case STATE_H_HDR:	// L_HDR -> H_BIT,L_RPT(H_STOP)
		if(MATCH(diff, DUR_H_HDR)) {
			rawData = 0;
			rawCount = 0;
			state = STATE_L_BIT;
		} else if(MATCH(diff, DUR_H_RPT)) {
			last_timer2 = millis();
			state = STATE_L_STOP;
		} else {
			state = STATE_L_STOP;
		}
		break;
	case STATE_L_BIT:	// H_BIT -> L_BIT,L_IDLE
		if(MATCH(diff, DUR_L_BIT)) {
			if(rawCount >= 32) {
				if((((rawData>>8)^rawData) & 0x00FF00FF) == 0x00FF00FF) {
					memset(&remoconData1, 0, sizeof(remoconData1));
					remoconData1.keys = (rawData>>16) & 0xFF; //0x00FF00FF;;
					last_timer2 = millis();
					updated = REMOTE_YES;
					digitalWrite(PORT_LED, 1);
				}
				state = STATE_H_IDLE;
			} else {
				state = STATE_H_BIT;
			}
		} else {
			state = STATE_H_IDLE;
		}
		break;
	case STATE_H_BIT:	// L_BIT -> H_BIT
		state = STATE_L_BIT;
		rawData = (rawData>>1);
		rawCount++;
		if(MATCH(diff, DUR_H_BIT1)) {
			rawData |= 0x80000000UL;
		} else if(MATCH(diff, DUR_H_BIT0)) {
			;
		} else {
			state = STATE_L_STOP;
		}
		break;
	case STATE_L_STOP:	// H_STOP -> L_IDLE
		state = STATE_H_IDLE;
		break;
	}
}

int remoconRobo_checkRemoteUpdated(int mergeKeys)
{
	if(last_timer2) {
	// pressed
		uint32_t timeout = (remoconData1.keys >= BUTTON_A_XY) ? DUR_H_TIMEOUT_A : DUR_H_TIMEOUT;
		if(millis() - last_timer2 < timeout) {
			if(updated == REMOTE_ANALOG) {
				static const uint8_t ButtonTable[] = {
					XY_RIGHT,
					XY_UP_R,
					0,
					XY_UP,
					0,
					0,
					0,
					XY_UP_L,
					XY_DOWN_R,
					0,
					0,
					0,
					XY_DOWN,
					0,
					XY_DOWN_L,
					XY_LEFT,
				};

				uint16_t lev = abs(remoconData1.x) + abs(remoconData1.y);
				if(lev >= 40) {
					uint8_t index = 0;
					if(remoconData1.x/2 <  remoconData1.y  ) index += 1;
					if(remoconData1.x   <  remoconData1.y/2) index += 2;
					if(remoconData1.x   < -remoconData1.y/2) index += 4;
					if(remoconData1.x/2 < -remoconData1.y  ) index += 8;

					remoconData1.xyKeys = ButtonTable[index];
					switch(remoconData1.xyKeys) {
					case XY_RIGHT:	lev =  remoconData1.x; break;
					case XY_LEFT:	lev = -remoconData1.x; break;
					case XY_UP:		lev =  remoconData1.y; break;
					case XY_DOWN:	lev = -remoconData1.y; break;
					default:		lev = lev/2; break;
					}
					if(lev > 256) lev = 255;
					remoconData1.xyLevel = lev;
				} else {
					remoconData1.xyKeys = 0;
					remoconData1.xyLevel = 0;
				}
				if(mergeKeys && remoconData1.keys == BUTTON_A_XY)
				    remoconData1.keys = remoconData1.xyKeys;
			}
			if(!remoconData2.keys && remoconData1.keys) {
			// 受信エラーにより歯抜けになる場合が多く、DUR_H_RPTが来たとき
				updated = REMOTE_YES;
				digitalWrite(PORT_LED, 1);
			}
			remoconData2 = remoconData1;
		} else if(remoconData2.keys) {
		// timeout & pressed -> released
			memset(&remoconData2, 0, sizeof(remoconData2));
			updated = REMOTE_YES;
			digitalWrite(PORT_LED, 0);
			last_timer2 = 0;
			last_timer3 = millis();
		}
	} else {
		if(!last_timer3) last_timer3 = millis();
		uint32_t diff = millis() - last_timer3;
		if(remoconData1.keys && diff > DUR_H_TIMEOUT)
			memset(&remoconData1, 0, sizeof(remoconData1));
		// buttonA押し -> buttonB押しでTOPが欠けREPが来たときbuttonAにならないようclear

		diff >>= 7;
	//	char buf[64]; sprintf(buf, "%d\r\n", diff); Serial.print(buf);
		if(diff == 0) {
			;
		} else if((diff % 16) == 0) {	// 2048
			digitalWrite(PORT_LED, 1);
		} else if((diff % 16) == 1) {
			digitalWrite(PORT_LED, 0);
		}
	}
	int _updated = updated;
	updated = 0;
	return _updated;
}

struct remoconData remoconRobo_getRemoteData(void)
{
	return remoconData2;
}

int remoconRobo_getRemoteKeys(void)
{
	return remoconData2.keys;
}

int remoconRobo_checkRemoteKey(void)
{
	remoconRobo_checkRemoteUpdated(1);
	return remoconData2.keys;
}

int remoconRobo_getRemoteX(void)
{
	return remoconData2.x;
}

int remoconRobo_getRemoteY(void)
{
	return remoconData2.y;
}

int remoconRobo_isRemoteKey(int key)
{
	return remoconData2.keys == key;
}

int remoconRobo_getRemoteCh(void)
{
	return analog_ch;
}

void remoconRobo_init(void)
{
	pinMode(PORT_LED, OUTPUT);

	TCCR0A=0x03; TCCR0B=0x03;	// timer0:8bit高速PWM, 1/64(977Hz), PWM6,5/timer

	pinMode(PORT_IR_RX,INPUT);
	attachInterrupt(0, irq_int0, CHANGE);

	state = STATE_H_IDLE;
	memset(&remoconData1, 0, sizeof(remoconData1));

//	Serial.begin(115200);
}
