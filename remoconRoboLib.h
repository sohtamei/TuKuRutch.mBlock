// copyright to SohtaMei 2019.

#ifndef remoconRobo_h
#define remoconRobo_h

void remoconRobo_init(void);
void remoconRobo_initCh4(void);

// Remote

enum {
// analog remote
	BUTTON_A_CENTER = 0x01,
	BUTTON_A_UP,
	BUTTON_A_RIGHT,
	BUTTON_A_LEFT,
	BUTTON_A_DOWN,

//NEC Code table
	BUTTON_A		= 0x45,
	BUTTON_B		= 0x46,
	BUTTON_C		= 0x47,
	BUTTON_D		= 0x44,
	BUTTON_E		= 0x43,
	BUTTON_UP		= 0x40,
	BUTTON_LEFT		= 0x07,
	BUTTON_CENTER	= 0x15,
	BUTTON_RIGHT	= 0x09,
	BUTTON_DOWN		= 0x19,
	BUTTON_F		= 0x0D,
	BUTTON_0		= 0x16,
	BUTTON_1		= 0x0C,
	BUTTON_2		= 0x18,
	BUTTON_3		= 0x5E,
	BUTTON_4		= 0x08,
	BUTTON_5		= 0x1C,
	BUTTON_6		= 0x5A,
	BUTTON_7		= 0x42,
	BUTTON_8		= 0x52,
	BUTTON_9		= 0x4A,
};

struct remoconData {
	int16_t  LR;
	int16_t  down_up;
	uint8_t  keys;
};

enum {
	REMOTE_OFF = 0,
	REMOTE_YES,
	REMOTE_ANALOG
};

int remoconRobo_checkRemote(void);
union remoconData remoconRobo_getRemoteData(void);
int remoconRobo_getRemoteLR(void);
int remoconRobo_getRemoteDownUp(void);
int remoconRobo_getRemoteKeys(void);
int remoconRobo_checkRemoteKey(int key);

// Tone

enum {
	T_C4=262, T_D4=294, T_E4=330, T_F4=349, T_G4=392, T_A4=440, T_B4=494,
	T_C5=523, T_D5=587, T_E5=659, T_F5=698,
};

void remoconRobo_tone(int sound, int ms);

// Motor

enum {
	CH_R,
	CH_L,
	CH3,
	CH4,
};

enum {
	DIR_FORWARD = 0,
	DIR_LEFT,
	DIR_RIGHT,
	DIR_BACK,
	DIR_ROLL_LEFT,
	DIR_ROLL_RIGHT,
};

void remoconRobo_setMotor(int ch, int speed);
void remoconRobo_setRobot(int direction, int speed);
void remoconRobo_setRobotLR(int speedL, int speedR);

int remoconRobo_calibRight(void);
int remoconRobo_calibLeft(void);
int remoconRobo_getCalib(void);

// MP3

void remoconRobo_initMP3(int volume);			// 0~30
void remoconRobo_playMP3(int track, int loop);
void remoconRobo_stopMP3(void);

#endif
