// copyright to SohtaMei 2019.

#include <stdint.h>
#include <stdlib.h>
#include <Arduino.h>
#include <util/delay.h>

#include "remoconRoboLib.h"

//#define DEF_CH4

static int speed = 255;
static const uint8_t SpeedTable[10] = { 48, 71, 94, 117, 140, 163, 186, 209, 232, 255};


void setup()
{
	remoconRobo_init();

//	Serial.begin(115200);
#ifdef DEF_CH4
	remoconRobo_initCh4();
#endif
	beep(T_C4);
	beep(T_D4);
	beep(T_E4);
//	char buf[64]; sprintf(buf, "%d\n", remoconRobo_getCalib()); Serial.print(buf);
}

void loop()
{
	while (1) {
		int remote = remoconRobo_checkRemote();
		if(remote) {
			union remoconData rData =  remoconRobo_getRemoteData();

			//char buf[64]; sprintf(buf, "%d, %d, %d\r\n", rData.keys, rData.down_up, rData.LR); Serial.print(buf);
			if(remote == REMOTE_ANALOG)
				remoconRobo_setRobotLR(rData.down_up + rData.LR,	// L
									 rData.down_up - rData.LR);	// R

			switch(rData.keys) {
			case BUTTON_A: if(!remoconRobo_calibLeft())  {beep(T_C4);} break;
		//	case BUTTON_B:
			case BUTTON_C: if(!remoconRobo_calibRight()) {beep(T_D4);} break;

			case BUTTON_A_RIGHT:
			case BUTTON_D:		remoconRobo_setMotor(CH3,  speed); break;
			case BUTTON_A_LEFT:
			case BUTTON_E:		remoconRobo_setMotor(CH3, -speed); break;

			case BUTTON_CENTER:
			case BUTTON_UP:		remoconRobo_setRobot(DIR_FORWARD, speed); break;
			case BUTTON_DOWN:	remoconRobo_setRobot(DIR_BACK,    speed); break;
		#ifdef DEF_CH4
			case BUTTON_LEFT:	remoconRobo_setRobot(DIR_ROLL_LEFT, speed); break;
			case BUTTON_RIGHT:	remoconRobo_setRobot(DIR_ROLL_RIGHT,speed); break;

			case BUTTON_A_UP:
			case BUTTON_0:		remoconRobo_setMotor(CH4,  1); break;
			case BUTTON_A_DOWN:
			case BUTTON_F:		remoconRobo_setMotor(CH4, -1); break;
		#else
			case BUTTON_LEFT:	remoconRobo_setRobot(DIR_LEFT,    speed); break;
			case BUTTON_RIGHT:	remoconRobo_setRobot(DIR_RIGHT,   speed); break;
			case BUTTON_0:		remoconRobo_setRobot(DIR_ROLL_LEFT, speed); break;
			case BUTTON_F:		remoconRobo_setRobot(DIR_ROLL_RIGHT,speed); break;
		#endif
			case BUTTON_1: beep(T_C4); speed = SpeedTable[1]; break;
			case BUTTON_2: beep(T_D4); speed = SpeedTable[2]; break;
			case BUTTON_3: beep(T_E4); speed = SpeedTable[3]; break;
			case BUTTON_4: beep(T_F4); speed = SpeedTable[4]; break;
			case BUTTON_5: beep(T_G4); speed = SpeedTable[5]; break;
			case BUTTON_6: beep(T_A4); speed = SpeedTable[6]; break;
			case BUTTON_7: beep(T_B4); speed = SpeedTable[7]; break;
			case BUTTON_8: beep(T_C5); speed = SpeedTable[8]; break;
			case BUTTON_9: beep(T_D5); speed = SpeedTable[9]; break;

			default:
				if(remote != REMOTE_ANALOG) remoconRobo_setRobotLR(0, 0);
				remoconRobo_setMotor(CH3, 0);
			#ifdef DEF_CH4
				remoconRobo_setMotor(CH4, 0);
			#endif
				break;
			}
		}
		delay(50);
	}
}

static void beep(int sound)
{
	remoconRobo_tone(sound, 300);
}
