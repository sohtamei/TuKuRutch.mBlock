#ifndef quadCrawler_h
#define quadCrawler_h

#include <stdint.h>

//動作速度定義
enum {
  quadCrawler_sslow = 2000,
  quadCrawler_slow  = 1000,
  quadCrawler_typical = 500,
  quadCrawler_fast  = 200,
  quadCrawler_high  = 100,
};

//制御ステート定義
enum {
  stop = 0,

  // repeat
  fw,
  cw,
  ccw,
  rw,
  Rigt,
  Left,

  // normal
  all_up,
  all_dn,
  h_up,
  t_up,
  r_up,
  l_up,

  // repeat
  all_h_up,
  l_r_up,
  all_up_dn,
};

void quadCrawler_Walk(uint16_t speed, uint8_t com);
void quadCrawler_setSpeed(uint16_t speed);

void quadCrawler_servoLoop(void);


void quadCrawler_init(void);

double quadCrawler_getSonner();
void quadCrawler_beep(int time);

void quadCrawler_colorWipe(uint8_t color);
enum {
  COLOR_OFF = 0,
  COLOR_RED,
  COLOR_GREEN,
  COLOR_BLUE,
  COLOR_YELLOW,
  COLOR_PURPLE,
  COLOR_LIGHTBLUE,
};

void quadCrawler_rainbow(uint8_t wait);

#endif  // quadCrawler_h
