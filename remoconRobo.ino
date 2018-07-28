#include <stdint.h>
#include <stdlib.h>
#include <Arduino.h>
#include <util/delay.h>

#include "familydayLibrary.h"

enum {
	T_C4=262, T_D4=294, T_E4=330, T_F4=349, T_G4=392, T_A4=440, T_B4=494,
	T_C5=523, T_D5=587, T_E5=659, T_F5=698,
};

static int speed = 255;
static const uint8_t SpeedTable[10] = { 48, 71, 94, 117, 140, 163, 186, 209, 232, 255};
static int calib = 0;

void setup()
{
	familyday_init();

	Serial.begin(9600);

	beep(T_C4);
	beep(T_D4);
	beep(T_E4);
}

void loop()
{
	while (1) {
		int key = familyday_getRemoteRiseFall();
		if(!(key & 0x100)) continue;
		char buf[64];
		sprintf(buf, "%04x\n", key); Serial.print(buf);
		switch(key & 0xFF) {
		case BUTTON_CENTER:
		case BUTTON_UP:		familyday_setRobot(DIR_FORWARD, speed, calib); digitalWrite(13, 1); break;
		case BUTTON_LEFT:	familyday_setRobot(DIR_LEFT,    speed, calib); digitalWrite(13, 1); break;
		case BUTTON_RIGHT:	familyday_setRobot(DIR_RIGHT,   speed, calib); digitalWrite(13, 1); break;
		case BUTTON_DOWN:	familyday_setRobot(DIR_BACK,    speed, calib); digitalWrite(13, 1); break;

		case BUTTON_D:		familyday_setMotor(2,  speed); digitalWrite(13, 1); break;
		case BUTTON_E:		familyday_setMotor(2, -speed); digitalWrite(13, 1); break;

		case BUTTON_A: beep(T_C4); calib++; break;
		case BUTTON_B: beep(T_D4); calib--; break;
		case BUTTON_C: beep(T_E4); break;

		case BUTTON_1: beep(T_C4); speed = SpeedTable[1]; break;
		case BUTTON_2: beep(T_D4); speed = SpeedTable[2]; break;
		case BUTTON_3: beep(T_E4); speed = SpeedTable[3]; break;
		case BUTTON_4: beep(T_F4); speed = SpeedTable[4]; break;
		case BUTTON_5: beep(T_G4); speed = SpeedTable[5]; break;
		case BUTTON_6: beep(T_A4); speed = SpeedTable[6]; break;
		case BUTTON_7: beep(T_B4); speed = SpeedTable[7]; break;
		case BUTTON_8: beep(T_C5); speed = SpeedTable[8]; break;
		case BUTTON_9: beep(T_D5); speed = SpeedTable[9]; break;

		default: familyday_setRobot(DIR_FORWARD, 0, 0); familyday_setMotor(2, 0); digitalWrite(13, 0); break;
		}
		delay(50);
	}
}

static void beep(int sound)
{
	familyday_tone(sound, 300);
}
