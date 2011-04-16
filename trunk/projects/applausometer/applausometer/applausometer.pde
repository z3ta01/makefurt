/*
$Id$

MAKEfurt Applausometer
Code vom untergeek
*/

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
#define STEP_DELAY 5
#define STEP_MAX 300
#define LEFT 1
#define RIGHT 2

// Das Array mit den Werten für die acht Einzelschritte. 
// 
// Zunächst die Pinzuweisungen.

const byte StepperIndex[4] = {
  STEP_AP, STEP_AN, STEP_BP, STEP_BN, } ;

const boolean StepperVal[8][4] = {
  {    1,0,0,1  },
  {    1,0,0,0  },
  {    1,0,1,0  },
  {    0,0,1,0  },
  {    0,1,1,0  },
  {    0,1,0,0  },
  {    0,1,0,1  },
  {    0,0,0,1  }
}; 

// Raucht der Kopf? Gut. Bester Link, um zu kapieren, was passiert:
// http://www.cvengineering.ch/index-Dateien/Der_Schrittmotor.htm


static int position = -1; // negativer Wert = Position nicht definiert
static byte hbstate = LOW;

// throw error, grind to a halt, give nothing back
void error(char* s) {
  Serial.println("---ERROR---");
  Serial.println(s);
  Serial.println("---STOP---");
  while (true) {
    heartBeat();
    delay(100);
  }
}

void heartBeat() {
  if (hbstate == LOW) hbstate = HIGH; else hbstate = LOW;
  digitalWrite(HEARTBEAT, hbstate);
}

boolean nullSensor()
{
  // Gibt true zurück, wenn die Nullposition erreicht und die Gabellichtschranke unterbrochen ist
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
  digitalWrite(STEP_BP,0);
  digitalWrite(STEP_AN,0);
  digitalWrite(STEP_BN,0);
}

void stepLeftOne()
{
    for (int s=0; s<8; s++)
    {
      for (int i=0; i<3; i++)
        digitalWrite(StepperIndex[i],StepperVal[s][i]);
      delay(STEP_DELAY);
    } 
  // Wir sind da, Strom abschalten
  shutdownStepper();
}

void stepRightOne()
{
    for (int s=8; s>0; s--) // von 7 bis 0
    {
      for (int i=0; i<3; i++)
        digitalWrite(StepperIndex[i],StepperVal[s][i]);
      delay(STEP_DELAY);
    } 
  // Wir sind da, Strom abschalten
  shutdownStepper();
}

void stepRelative(int steps) {
  if (steps < 0) {
    for (int i=steps; i!=0; i++) stepLeftOne();
  } else {
    for (int i=steps; i!=0; i--) stepRightOne();
  }
}


void stepAbsolute(int dest) {
  stepRelative(dest-position); 
}


void setup()
{
  Serial.begin(38400);
  Serial.print("ON..");
  // hearteat init
  pinMode(HEARTBEAT, OUTPUT);
  digitalWrite(HEARTBEAT, LOW);
  // lichtschranke init
  pinMode (GATE_END, INPUT);
  digitalWrite (GATE_END, HIGH);
  // stepper init
  pinMode (STEP_AP, OUTPUT);
  pinMode (STEP_BP, OUTPUT);
  pinMode (STEP_AN, OUTPUT);
  pinMode (STEP_BN, OUTPUT);
  //zeroStepper();
  Serial.println("OK");
}

void loop()
{
  heartBeat();
  stepRelative(10);
  delay(1000);
  stepRelative(-10);
  delay(1500);
}



