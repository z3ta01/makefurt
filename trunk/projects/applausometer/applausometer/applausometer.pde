/*
$Id$

MAKEfurt Applausometer
Code vom untergeek und vom byteborg

TODO:
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
// analog
#define ANPIN 1

// button config
#define BOUNCE_TIME 100
Bounce button = Bounce(BUTTON_START, BOUNCE_TIME);

// stepper config & vars
#define STEP_DELAY 2
#define STEP_MAX 765  //ausprobiert; 5.5.2011 untergeek
#define LEFT 1
#define RIGHT 2
const byte StepperIndex[4] = {
  STEP_AP, STEP_AN, STEP_BP, STEP_BN,
} ;
const boolean StepperVal[8][4] = {
  { 1,0,1,0 },
  { 0,1,1,0 },
  { 0,1,0,1 },
  { 1,0,0,1 },
}; 
static int position = -1; // negativer Wert = Position nicht definiert
// Raucht der Kopf? Gut. Bester Link, um zu kapieren, was passiert:
// http://www.cvengineering.ch/index-Dateien/Der_Schrittmotor.htm


// Heartbeat State
static byte hbstate = LOW;

// Sampling Setup & Buffer
#define BUFSIZE 256 // wieviel Punkte sampeln?
#define MAINDELAY 100 // ms
int slen = 0;
int sbuf[BUFSIZE];
#define AN_INTERP 5 // Stützstellen Interpolation
#define AN_INTERD 7 // Delay für Interpolation in ms


/***
 *** Utility Stuff
 ***/
   
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

/***
 *** Stepper Operation
 ***/
 
// Schauen, ob der Stepper den Schlitten in die Null gefahren hat
// Gibt true zurück, wenn die Nullposition erreicht und die Gabellichtschranke unterbrochen ist
boolean nullSensor()
{
  return (digitalRead(GATE_END) == 1); 
}

// Stepper in Nullposition fahren ("Kalibrieren")
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

// Motor abschalten
void shutdownStepper() {
  digitalWrite(STEP_AP,0);
  digitalWrite(STEP_AN,0);
  digitalWrite(STEP_BP,0);
  digitalWrite(STEP_BN,0);
}

// eins nach links steppen
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

// eins nach rechts steppen
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

// relativ positionieren
void stepRelative(int steps) {
  if (steps < 0) {
    for (int i=steps; i!=0; i++) _stepLeftOne();
  } else {
    for (int i=steps; i!=0; i--) _stepRightOne();
  }
  // Wir sind da, Strom abschalten
  shutdownStepper();
  position = position + steps;
}

// absolut positionieren
void stepAbsolute(int dest) {
  stepRelative(dest-position); 
}

/***
 *** Analog Input: Lautstärke messen
 ***/

/*
Lautstärkemessung - Theory of Operation

1. initSampling() setzt den Messdatenspeicher zurück

2. sample() wird mit einer vorgegebenen Frequenz (Main-Loop? Timer?) 
   aufgerufen und schreibt Messdaten in den Puffer

3. int finishSampling() ermittelt den Durchschnitt im 
   Puffer und gibt ihn zurück
*/

void startSampling() { 
  slen = 0;
}

void sample() {
  byte b = 0;
  long inbuf = 0;
  for (b=0; b<AN_INTERP; b++) {
    inbuf =+ analogRead(ANPIN);
    delay(AN_INTERD);
  }
  sbuf[slen] = inbuf / AN_INTERP;
  slen++;
}

int finishSampling() {
  // return average of sampled values
  return 123;
}

/***
 *** Arduino initialisieren
 ***/

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


/***
 *** Arduino laufen lassen (main loop)
 ***/

int runstate = 0; // Laufzeit Statusvariable
void loop()
{
  heartBeat(); // blinken
  
  if (button.update()) { // knopp auslesen
    if (button.fallingEdge()) { // knopp gedrückt
      if (runstate == 0) { // 0 ist stop, nichtstun
      Serial.print("messen...");
        startSampling();
        runstate = 1; // nächstes: messung
      } 
    } // knopp gedrückt
  } // knopp auslesen
  
  if (runstate == 1) { // 1 == messen
    sample();
    if (slen >= BUFSIZE) {
      runstate = 2;
    }
  } else if (runstate == 2) { // 2 == ausgeben
    stepAbsolute(finishSampling());
    runstate = 0; // stop
  }
    
  delay(MAINDELAY);
}



