#include <stdint.h>
//#include <Wire.h> is necessary in .ino
#include <Adafruit_PWMServoDriver.h>
#include <Adafruit_NeoPixel.h>
#include "quadCrawler.h"

#define Sw1 3
#define Sw2 4
#define Sw3 5
#define Sw4 6

#define Bz 8    // Bzzer Pin
#define Echo A0 // Echo Pin
#define Trig A1 // Trigger Pin

Adafruit_PWMServoDriver pwm = Adafruit_PWMServoDriver();
#define servo_min 200  // Min pulse length out of 4096
#define servo_max 400 // Max pulse length out of 4096
#define deg_max   130  // Max deg
#define deg_min   20   // Min deg


//各サーボ定義
//Right Front Knee SV1-1
#define RFK  1
unsigned int RFK_c = 70;
unsigned int RFK_d = 70;
//Right Front Crach SV1-3
#define RFC  0
unsigned int  RFC_c = 90;
unsigned int RFC_d = 90;
//Right Rear Knee SV3-1
#define RRK  5
unsigned int RRK_c = 68;
unsigned int RRK_d = 68;
//Right Rear Crach SV3-4
#define RRC  4
unsigned int RRC_c = 90;
unsigned int RRC_d = 90;
//Left Front Knee SV2-1
#define LFK  3
unsigned int LFK_c = 90;
unsigned int LFK_d = 90;
//Left Front Crach SV2-4
#define LFC  2
unsigned int LFC_c = 90;
unsigned int LFC_d = 90;
//Left Rear Knee SV4-1
#define LRK  7
unsigned int LRK_c = 90;
unsigned int LRK_d = 90;
//Left Rear Crach SV4-4
#define LRC  6
unsigned int LRC_c = 90;
unsigned int LRC_d = 90;

#define RFK_D 80
#define RFC_F 90
#define RRK_D 75
#define RRC_F 110
#define LFK_D 80
#define LFC_F 80
#define LRK_D 80
#define LRC_F 60

#define RFK_U 58
#define RFC_R 60
#define RRK_U 55
#define RRC_R 80
#define LFK_U 105
#define LFC_R 110
#define LRK_U 103
#define LRC_R 90

#define RFK_N 70
#define RFC_N 85
#define RRK_N 68
#define RRC_N 90
#define LFK_N 90
#define LFC_N 90
#define LRK_N 90
#define LRC_N 90


#define RFK_UD 130
#define RRK_UD 130
#define LFK_UD 20
#define LRK_UD 20


enum {
  ServoOff = 0,
  ServoNeutral,
  ServoNormal,
  ServoRepeat0,
  ServoRepeat1,
  ServoRepeat2,
  ServoRepeat3,
};

static uint8_t  servoState = 0;
static uint32_t servoTime = 0;
static uint16_t servoDelay = quadCrawler_fast;
static const uint8_t (*servoMotion)[8] = NULL;

extern volatile unsigned long timer0_millis;


static void set_servo_deg(uint8_t id, unsigned int deg) {
  const uint8_t channel_table[] = {RFK, RFC, RRK, RRC, LFK, LFC, LRK, LRC};
  uint8_t channel = channel_table[id];
  unsigned int setdata;
  setdata = (unsigned int)((deg - deg_min) *  (servo_max - servo_min) / (deg_max - deg_min)) + servo_min;
  //  Serial.print ("setdata:");
  //  Serial.println (setdata);
  if (setdata <= servo_max) {
    if (setdata >= servo_min) {
      pwm.setPWM(channel, 0, setdata);
      delay(20);
      //      //Serial.print(setdata);
    }
    else {
      //      //Serial.print (setdata);
      //Serial.println ("add or deg value error < min");
    }
  }
  else {
    //    //Serial.print (setdata);
    //Serial.println ("deg value error > max");
  }
}

static void set_servo_deg8(const uint8_t motion[8], uint8_t state) {
  uint8_t i;
  for(i = 0; i < 8; i++) {
    if(motion[i] != -1)
      set_servo_deg(i, motion[i]);
  }
  servoState = state;
  servoTime = timer0_millis;
}

static void set_servo_motion(const uint8_t (*motion)[8], uint8_t state) {
  servoMotion = motion;
  set_servo_deg8(motion[0], state);
}

static void set_servo_off8(uint8_t state) {
  uint8_t i;
  for(i = 0; i < 8; i++)
    pwm.setPWM(i, 0, 0);
  servoState = state;
  servoTime = timer0_millis;
}

static void sv_init() {
  const uint8_t motion[] = {RFK_N, RFC_N, RRK_N, RRC_N, LFK_N, LFC_N, LRK_N, LRC_N};
  set_servo_motion(&motion, ServoNeutral);
}

void quadCrawler_servoLoop(void)
{
  // サーボOFFか、delay時間が経過してないとき
  if(!servoState || (timer0_millis - servoTime) < servoDelay)
    return;

  // normal-なにもしない、repeat-動作を繰り返し
  switch(servoState) {
  case ServoRepeat0:
    set_servo_deg8(servoMotion[1], ServoRepeat1);
    break;
  case ServoRepeat1:
    set_servo_deg8(servoMotion[2], ServoRepeat2);
    break;
  case ServoRepeat2:
    set_servo_deg8(servoMotion[3], ServoRepeat3);
    break;
  case ServoRepeat3:
    set_servo_deg8(servoMotion[0], ServoRepeat0);
    break;
  case ServoNeutral:
    set_servo_off8(ServoOff);
    break;
  }
}

void quadCrawler_setSpeed(uint16_t speed) {
  servoDelay = speed;
}

static uint8_t cur_com = stop;

void quadCrawler_Walk(uint16_t speed, uint8_t com) {
  servoDelay = speed;

  if (cur_com == com) return;
  cur_com = com;

  if (com == stop) {
    const uint8_t motion[] = {RFK_N, RFC_N, RRK_N, RRC_N, LFK_N, LFC_N, LRK_N, LRC_N};

    // normal, repeatのとき : neutral姿勢
    if(servoState != ServoNeutral && servoState != ServoOff) {
      set_servo_motion(&motion, ServoNeutral);
    }
  }
  else if (com == fw) {
    //Serial.println ("-fw");
    static const uint8_t motion[4][8] = {
                           {-1,    RFC_F, -1,    RRC_R, -1,    LFC_R, -1,    LRC_F},
                           {RFK_D, -1,    RRK_U, -1,    LFK_U, -1,    LRK_D, -1,  },
                           {-1,    RFC_R, -1,    RRC_F, -1,    LFC_F, -1,    LRC_R},
                           {RFK_U, -1,    RRK_D, -1,    LFK_D, -1,    LRK_U, -1,  }};
    set_servo_motion(motion, ServoRepeat0);
  }
  else if (com == rw) {
    //Serial.println ("-rw");
    static const uint8_t motion[4][8] = {
                           {-1,    RFC_F, -1,    RRC_R, -1,    LFC_R, -1,    LRC_F},
                           {RFK_U, -1,    RRK_D, -1,    LFK_D, -1,    LRK_U, -1,  },
                           {-1,    RFC_R, -1,    RRC_F, -1,    LFC_F, -1,    LRC_R},
                           {RFK_D, -1,    RRK_U, -1,    LFK_U, -1,    LRK_D, -1,  }};
    set_servo_motion(motion, ServoRepeat0);
  }
  else if (com == cw) {
    //Serial.println ("-cw");
    static const uint8_t motion[4][8] = {
                           {-1,    RFC_F, -1,    RRC_R, -1,    LFC_F, -1,    LRC_R},
                           {RFK_U, -1,    RRK_D, -1,    LFK_D, -1,    LRK_U, -1,  },
                           {-1,    RFC_R, -1,    RRC_F, -1,    LFC_R, -1,    LRC_F},
                           {RFK_D, -1,    RRK_U, -1,    LFK_U, -1,    LRK_D, -1,  }};
    set_servo_motion(motion, ServoRepeat0);
  }
  else if (com == ccw) {
    //Serial.println ("-ccw");
    static const uint8_t motion[4][8] = {
                           {-1,    RFC_F, -1,    RRC_R, -1,    LFC_F, -1,    LRC_R},
                           {RFK_D, -1,    RRK_U, -1,    LFK_U, -1,    LRK_D, -1,  },
                           {-1,    RFC_R, -1,    RRC_F, -1,    LFC_R, -1,    LRC_F},
                           {RFK_U, -1,    RRK_D, -1,    LFK_D, -1,    LRK_U, -1,  }};
    set_servo_motion(motion, ServoRepeat0);
  }
  else if (com == Rigt) {
    //Serial.println ("-right");
    static const uint8_t motion[4][8] = {
                           {-1,    RFC_F, -1,    RRC_F, -1,    LFC_F, -1,    LRC_F},
                           {RFK_U, -1,    RRK_D, -1,    LFK_D, -1,    LRK_U, -1,  },
                           {-1,    RFC_R, -1,    RRC_R, -1,    LFC_R, -1,    LRC_R},
                           {RFK_D, -1,    RRK_U, -1,    LFK_U, -1,    LRK_D, -1,  }};
    set_servo_motion(motion, ServoRepeat0);
  }
  else if (com == Left) {
    //Serial.println ("-right");
    static const uint8_t motion[4][8] = {
                           {-1,    RFC_F, -1,    RRC_F, -1,    LFC_F, -1,    LRC_F},
                           {RFK_D, -1,    RRK_U, -1,    LFK_U, -1,    LRK_D, -1   },
                           {-1,    RFC_R, -1,    RRC_R, -1,    LFC_R, -1,    LRC_R},
                           {RFK_U, -1,    RRK_D, -1,    LFK_D, -1,    LRK_U, -1   }};
    set_servo_motion(motion, ServoRepeat0);
  }
/*
  else if (com == nt) {
    //Serial.println ("-nutral");
    const uint8_t motion[] = {RFK_N, RFC_N, RRK_N, RRC_N, LFK_N, LFC_N, LRK_N, LRC_N};
    set_servo_motion(&motion, ServoNormal);
  }
*/
  else if (com == all_up) {
    //Serial.println ("-all up");
    const uint8_t motion[] = {RFK_U, -1,    RRK_U, -1,    LFK_U, -1,    LRK_U, -1   };
    set_servo_motion(&motion, ServoNormal);
  }
  else if (com == all_dn) {
    //Serial.println ("-all down");
    const uint8_t motion[] = {RFK_UD,-1,    RRK_UD,-1,    LFK_UD,-1,    LRK_UD,-1   };
    set_servo_motion(&motion, ServoNormal);
  }
  else if (com == h_up) {
    //Serial.println ("-Hip up");
    const uint8_t motion[] = {RFK_U, -1,    RRK_UD,-1,    LFK_U, -1,    LRK_UD,-1   };
    set_servo_motion(&motion, ServoNormal);
  }
  else if (com == t_up) {
    //Serial.println ("-Top up");
    const uint8_t motion[] = {RFK_UD,-1,    RRK_U, -1,    LFK_UD,-1,    LRK_U, -1   };
    set_servo_motion(&motion, ServoNormal);
  }
  else if (com == r_up) {
    //Serial.println ("-Right up");
    const uint8_t motion[] = {RFK_U, -1,    RRK_U, -1,    LFK_UD,-1,    LRK_UD,-1   };
    set_servo_motion(&motion, ServoNormal);
  }
  else if (com == l_up) {
    //Serial.println ("Left up");
    const uint8_t motion[] = {RFK_UD,-1,    RRK_UD,-1,    LFK_U, -1,    LRK_U, -1   };
    set_servo_motion(&motion, ServoNormal);
  }
  else if (com == all_h_up) {
    static const uint8_t motion[4][8] = {
                           {RFK_U, -1,    RRK_U, -1,    LFK_U, -1,    LRK_U, -1   },
                           {RFK_U, -1,    RRK_UD,-1,    LFK_U, -1,    LRK_UD,-1   },
                           {RFK_U, -1,    RRK_U, -1,    LFK_U, -1,    LRK_U, -1   },
                           {RFK_U, -1,    RRK_UD,-1,    LFK_U, -1,    LRK_UD,-1   }};
    set_servo_motion(motion, ServoRepeat0);
  }
  else if (com == l_r_up) {
    static const uint8_t motion[4][8] = {
                           {RFK_UD,-1,    RRK_UD,-1,    LFK_U, -1,    LRK_U, -1   },
                           {RFK_U, -1,    RRK_U, -1,    LFK_UD,-1,    LRK_UD,-1   },
                           {RFK_UD,-1,    RRK_UD,-1,    LFK_U, -1,    LRK_U, -1   },
                           {RFK_U, -1,    RRK_U, -1,    LFK_UD,-1,    LRK_UD,-1   }};
    set_servo_motion(motion, ServoRepeat0);
  }
  else if (com == all_up_dn) {
    static const uint8_t motion[4][8] = {
                           {RFK_U, -1,    RRK_U, -1,    LFK_U, -1,    LRK_U, -1   },
                           {RFK_UD,-1,    RRK_UD,-1,    LFK_UD,-1,    LRK_UD,-1   },
                           {RFK_U, -1,    RRK_U, -1,    LFK_U, -1,    LRK_U, -1   },
                           {RFK_UD,-1,    RRK_UD,-1,    LFK_UD,-1,    LRK_UD,-1   }};
    set_servo_motion(motion, ServoRepeat0);
  }
  else {

  }
}


#define Neopix A2
Adafruit_NeoPixel strip = Adafruit_NeoPixel(8, Neopix, NEO_GRB + NEO_KHZ800);

static void colorWipe(uint32_t c, uint8_t wait) {
  for (uint16_t i = 0; i < strip.numPixels(); i++) {
    strip.setPixelColor(i, c);
    strip.show();
    delay(wait);
  }
}

void quadCrawler_colorWipe(uint8_t color) {
  switch(color) {
  case COLOR_RED:
    colorWipe(strip.Color(255,0,0), 10);
    break;
  case COLOR_GREEN:
    colorWipe(strip.Color(0,255,0), 10);
    break;
  case COLOR_BLUE:
    colorWipe(strip.Color(0,0,255), 10);
    break;
  case COLOR_YELLOW:
    colorWipe(strip.Color(128,128,0), 10);
    break;
  case COLOR_PURPLE:
    colorWipe(strip.Color(128,0,128), 10);
    break;
  case COLOR_LIGHTBLUE:
    colorWipe(strip.Color(0,128,128), 10);
    break;
  default:
    break;
  }
}

static uint32_t Wheel(byte WheelPos) {
  WheelPos = 255 - WheelPos;
  if (WheelPos < 85) {
    return strip.Color(255 - WheelPos * 3, 0, WheelPos * 3);
  }
  if (WheelPos < 170) {
    WheelPos -= 85;
    return strip.Color(0, WheelPos * 3, 255 - WheelPos * 3);
  }
  WheelPos -= 170;
  return strip.Color(WheelPos * 3, 255 - WheelPos * 3, 0);
}

void quadCrawler_rainbow(uint8_t wait) {
  uint16_t i, j;

  for (j = 0; j < 256; j++) {
    for (i = 0; i < strip.numPixels(); i++) {
      strip.setPixelColor(i, Wheel((i + j) & 255));
    }
    strip.show();
    delay(wait);
  }
}
/*
static void theaterChaseRainbow(uint8_t wait) {
  for (int j = 0; j < 256; j++) {   // cycle all 256 colors in the wheel
    for (int q = 0; q < 3; q++) {
      for (uint16_t i = 0; i < strip.numPixels(); i = i + 3) {
        strip.setPixelColor(i + q, Wheel( (i + j) % 255)); //turn every third pixel on
      }
      strip.show();

      delay(wait);

      for (uint16_t i = 0; i < strip.numPixels(); i = i + 3) {
        strip.setPixelColor(i + q, 0);      //turn every third pixel off
      }
    }
  }
}
*/


double quadCrawler_getSonner() {
  double data;
  double distance;
  digitalWrite(Trig, LOW);
  delayMicroseconds(2);
  digitalWrite(Trig, HIGH );
  delayMicroseconds(10);
  digitalWrite(Trig, LOW );
  data = pulseIn(Echo, HIGH );
  if (data > 0) {
    distance = data * 0.017;
    return distance;
  }
  else {
    return 0;
  }
}

void quadCrawler_beep(int time) {
  for (int i = 0; i < time; i++) {
    digitalWrite(Bz, HIGH);
    delayMicroseconds(400);
    digitalWrite(Bz, LOW );
    delayMicroseconds(400);
  }
}


void quadCrawler_init(void)
{
  pinMode( Echo, INPUT );
  pinMode( Trig, OUTPUT );
  pinMode( Bz, OUTPUT );
  pinMode( Sw1, INPUT_PULLUP );
  pinMode( Sw2, INPUT_PULLUP );
  pinMode( Sw3, INPUT_PULLUP );
  pinMode( Sw4, INPUT_PULLUP );

//  Serial.begin(9600);
//  Serial.println("SUNA KOMA test!");
  strip.begin();
  strip.show(); // Initialize all pixels to 'off'
  pwm.begin();
  pwm.setPWMFreq(50);  // Analog servos run at ~50 Hz updates
  yield();
  sv_init();
}

