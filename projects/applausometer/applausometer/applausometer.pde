/*
$Id$

MAKEfurt Applausometer
Code vom untergeek und vom byteborg

TODO:
- Maximalanzahl von Steps herausfinden
- Analog-Input-Lautstärkemeter an den Analog-In anbasteln

*/

#include <Bounce.h>

// PIN mapping
// OUT
#define HEARTBEAT 13
#define STEP_AP 8
#define STEP_AN 7
#define STEP_BP 4
#define STEP_BN 2
#define LAMP 6

// IN
#define BUTTON_START 5
#define GATE_END 3

// stepper config
#define STEP_DELAY 2
#define STEP_MAX 3000
#define LEFT 1
#define RIGHT 2

// button config
#define BOUNCE_TIME 100
Bounce button = Bounce(BUTTON_START, BOUNCE_TIME);

const byte StepperIndex[4] = {
  STEP_AP, STEP_AN, STEP_BP, STEP_BN,
} ;

const boolean StepperVal[8][4] = {
{    1,0,1,0  },
  {    0,1,1,0  },
  {    0,1,0,1  },
  {    1,0,0,1  },
}; 

// Raucht der Kopf? Gut. Bester Link, um zu kapieren, was passiert:
// http://www.cvengineering.ch/index-Dateien/Der_Schrittmotor.htm


static int position = -1; // negativer Wert = Position nicht definiert
static byte hbstate = LOW;

// throw error, grind to a halt, give nothing back ;-)
void error(char* s) {
  Serial.println("---ERROR---");
  Serial.println(s);
  Serial.println("---STOP---");
  while (true) {
    heartBeat();
    delay(1000);
  }
}

// wir wollen die LED auf dem Brett ab und an blinken lassen, damit
// wir sehen können, ob was tot ist, oder wir noch leben
void heartBeat() {
  if (hbstate == LOW) hbstate = HIGH; else hbstate = LOW;
  digitalWrite(HEARTBEAT, hbstate);
}

// Schauen, ob der Stepper den Schlitten in die Null gefahren hat
// Gibt true zurück, wenn die Nullposition erreicht und die Gabellichtschranke unterbrochen ist
boolean nullSensor()
{
  return (digitalRead(GATE_END) == 1); 
}


void zeroStepper()
{
  int safetyCount = position; //bei definierter Position: maximal so viele Schritte nach links
  if (position < 0) 
    safetyCount = STEP_MAX; //wenn nicht definiert: maximale Schrittzahl = definierte Breite des ges. Wegs. 
  while (!nullSensor()) {
    stepRelative(-1); 
    safetyCount--;
    if (safetyCount <=0)  error("zeroStepper() reached safetyCount");
  }
  position = 0; 

}

void shutdownStepper() {
  digitalWrite(STEP_AP,0);
  digitalWrite(STEP_AN,0);
  digitalWrite(STEP_BP,0);
  digitalWrite(STEP_BN,0);
}

void _stepLeftOne()
{
    for (int s=0; s<4; s++)
    {
      for (int i=0; i<4; i++) {
        digitalWrite(StepperIndex[i],StepperVal[s][i]);
      }
      delay(STEP_DELAY);
    }
}

void _stepRightOne()
{
  int s;
  int i;
    for (s=0; s<4; s++)
    {
      for (i=0; i<4; i++) {
        digitalWrite(StepperIndex[i],StepperVal[3-s][i]);
      }
      delay(STEP_DELAY);
    } 
}

void stepRelative(int steps) {
  if (steps < 0) {
    for (int i=steps; i!=0; i++) _stepLeftOne();
  } else {
    for (int i=steps; i!=0; i--) _stepRightOne();
  }
  // Wir sind da, Strom abschalten
  shutdownStepper();
}


void stepAbsolute(int dest) {
  stepRelative(dest-position); 
}


void setup()
{
  Serial.begin(38400);
  Serial.print("1");
  // hearteat init
  pinMode(HEARTBEAT, OUTPUT);
  digitalWrite(HEARTBEAT, LOW);
  // lichtschranke init
  Serial.print("2");
  pinMode (GATE_END, INPUT);
  digitalWrite (GATE_END, HIGH);
  // button init
  Serial.print("3");
  pinMode(BUTTON_START, INPUT);
  digitalWrite(BUTTON_START, HIGH);
  // stepper init
  Serial.print("3");
  pinMode (STEP_AP, OUTPUT);
  pinMode (STEP_BP, OUTPUT);
  pinMode (STEP_AN, OUTPUT);
  pinMode (STEP_BN, OUTPUT);
  zeroStepper();
  Serial.println(" OK");
}

int runstate = 0;
void loop()
{
  heartBeat();
  if (button.update()) { // knopp auslesen
    if (button.fallingEdge()) { // knopp gedrückt
      if (runstate == 0) { // fahren
      Serial.print("0");
        stepRelative(500);
        runstate = 1; // danach: zurückfahren
      } else if (runstate == 1) { // zurückfahren
      Serial.print("1");
        stepRelative(-500);
        runstate = 0; // danach: wieder fahren
      }
    } // knopp gedrückt
  } // knopp auslesen
  delay(100);
}



