#ifndef familyday_h
#define familyday_h

//NEC Code table
#define BUTTON_A		0x45
#define BUTTON_B		0x46
#define BUTTON_C		0x47
#define BUTTON_D		0x44
#define BUTTON_E		0x43
#define BUTTON_UP		0x40
#define BUTTON_LEFT		0x07
#define BUTTON_CENTER	0x15
#define BUTTON_RIGHT	0x09
#define BUTTON_DOWN		0x19
#define BUTTON_F		0x0D
#define BUTTON_0		0x16
#define BUTTON_1		0x0C
#define BUTTON_2		0x18
#define BUTTON_3		0x5E
#define BUTTON_4		0x08
#define BUTTON_5		0x1C
#define BUTTON_6		0x5A
#define BUTTON_7		0x42
#define BUTTON_8		0x52
#define BUTTON_9		0x4A

enum {
	DIR_FORWARD = 0,
	DIR_LEFT,
	DIR_RIGHT,
	DIR_BACK,
	DIR_ROLL_LEFT,
	DIR_ROLL_RIGHT,
};

void familyday_init(void);
void familyday_initRemote(void);
int familyday_getRemote(void);
int familyday_getRemoteUpdated(void);
int familyday_checkRemote(int key);
void familyday_tone(int sound, int ms);
void familyday_setMotor(int ch, int speed);
void familyday_setRobot(int direction, int speed);
int familyday_calibRight(void);
int familyday_calibLeft(void);
int familyday_getCalib(void);

#endif
