// copyright to SohtaMei 2019.

#ifndef quadCrawlerRemocon_t
#define quadCrawlerRemocon_t

struct remoconData {
	int16_t  x;
	int16_t  y;
	uint8_t  keys;
	uint8_t  xyKeys;	// joystick direction
	uint8_t  xyLevel;	// joystick level
};

enum {
//NEC Code table
	BUTTON_POWER	= 0x45,
	BUTTON_B		= 0x46,
	BUTTON_MENU		= 0x47,
	BUTTON_TEST		= 0x44,
	BUTTON_RETURN	= 0x43,
	BUTTON_C		= 0x0D,

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

// joystick direction
enum {
	XY_UP_R			= 0x70,
	XY_UP,
	XY_UP_L,
	XY_RIGHT,
	XY_LEFT,
	XY_DOWN_R,
	XY_DOWN,
	XY_DOWN_L,
};

void remoconRobo_init(void);

int remoconRobo_checkRemoteUpdated(int mergeKeys);		// update remoconData, return REMOTE_xx

enum {
	REMOTE_OFF = 0,
	REMOTE_YES,
	REMOTE_ANALOG,
};


struct remoconData remoconRobo_getRemoteData(void);		// return remoconData

// for scratch
int remoconRobo_getRemoteX(void);						// return remoconData.x
int remoconRobo_getRemoteY(void);						// return remoconData.y
int remoconRobo_isRemoteKey(int key);					// return (remoconData.xyKeys == key)

int remoconRobo_getRemoteKeys(void);					// return remoconData.keys
int remoconRobo_checkRemoteKey(void);					// update remoconData, return remoconData.keys

int remoconRobo_getRemoteCh(void);

#endif  // quadCrawlerRemocon_t
