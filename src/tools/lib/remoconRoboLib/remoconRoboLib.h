// copyright to SohtaMei 2019.

#ifndef remoconRobo_h
#define remoconRobo_h

void remoconRobo_init(void);
void remoconRobo_initCh4(void);

// Remote

enum {
//NEC Code table
#if 0
	BUTTON_A		= 0x45,
	BUTTON_B		= 0x46,
	BUTTON_C		= 0x47,
	BUTTON_D		= 0x44,
	BUTTON_E		= 0x43,
	BUTTON_F		= 0x0D,
#else
	BUTTON_POWER	= 0x45,
	BUTTON_B		= 0x46,
	BUTTON_MENU		= 0x47,
	BUTTON_TEST		= 0x44,
	BUTTON_RETURN	= 0x43,
	BUTTON_C		= 0x0D,
#endif
	BUTTON_UP		= 0x40,
	BUTTON_LEFT		= 0x07,
	BUTTON_CENTER	= 0x15,
	BUTTON_RIGHT	= 0x09,
	BUTTON_DOWN		= 0x19,
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

// analog remote
	BUTTON_A_XY		= 0x60,
	BUTTON_A_CENTER = 0x61,
	BUTTON_A_UP		= 0x62,
	BUTTON_A_RIGHT	= 0x63,
	BUTTON_A_LEFT	= 0x64,
	BUTTON_A_DOWN	= 0x65,
};

struct remoconData {
	int16_t  x;
	int16_t  y;
	uint8_t  keys;
};

enum {
	REMOTE_OFF = 0,
	REMOTE_YES,
	REMOTE_ANALOG,
};

int remoconRobo_checkRemoteUpdated(void);
int remoconRobo_checkRemoteKey(void);
struct remoconData remoconRobo_getRemoteData(void);
int remoconRobo_getRemoteX(void);
int remoconRobo_getRemoteY(void);
int remoconRobo_getRemoteKeys(void);
int remoconRobo_isRemoteKey(int key);
int remoconRobo_getRemoteCh(void);

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

int remoconRobo_getCalib(void);
int remoconRobo_setCalib(int calib);
int remoconRobo_incCalib(int offset);

// MP3

void remoconRobo_initMP3(int volume);			// 0~30
void remoconRobo_playMP3(int track, int loop);
void remoconRobo_stopMP3(void);

uint16_t remoconRobo_getAnalog(uint8_t ch, uint16_t count);

#endif
