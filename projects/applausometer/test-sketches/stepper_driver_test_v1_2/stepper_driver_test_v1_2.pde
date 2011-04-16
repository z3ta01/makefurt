// Ansteuercode für Applausometer-Schrittmotor (den Zeiger)
// April 2011 untergeek / abrowdi
// V1.2, 12.4.2011

// Pinbelegung: Phasen A, B, A-, B-
// Unser Motor - ein M35SP-9T von Mitsumi - ist zwar laut Datenblatt ein unipolarer Motor
// (jede Spule ist praktisch in beide Richtungen gewickelt), 
// wird aber bipolar betrieben - jeder komplette Zyklus des Motors besteht aus acht Einzelschritten.

// Wer mag, kann sich - für spätere Anwendungen - schon mal einen Code ausdenken, 
// der nicht auf Zyklen genau positioniert, sondern auf Einzelschritte...


// Konstanten
// Die beiden Pole der Spule A
const int StepperAPin = 8; 
const int StepperANegPin = 7;
// Die beiden Pole der Spule B
const int StepperBPin = 4;
const int StepperBNegPin = 2; 

// Gabellichtschranke
const int StepperLED = 3;
const int StartButton = 5; // Eingang
const int TriacOut= 6 ; // Ausgang, um die Lampen zu schalten. PWM = Dimmer für Phasenanschnittsteuerung.

// Mikroeingang (nach Vorverstärker)
const int MicInput = 1;


const int StepperDelay=2; // ja, wirklich - das reicht!
const int MaxSteps = 9999; //anpassen; Breite in Schritten =maximale Bewegung

// Das Array mit den Werten für die acht Einzelschritte. 
// 
// Zunächst die Pinzuweisungen.

const byte StepperIndex[4] = {
  StepperAPin, StepperANegPin, StepperBPin, StepperBNegPin, } ;


// Jetzt die acht Einzelschritte pro Zyklus:

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


boolean NullSensor()
{
  // Gibt true zurück, wenn die Nullposition erreicht und die Gabellichtschranke unterbrochen ist
  return digitalRead(StepperLED); 
}


boolean zeroMotor()
{
  int safetyCount = position; //bei definierter Position: maximal so viele Schritte nach links
  if (position < 0) 
    safetyCount = MaxSteps; //wenn nicht definiert: maximale Schrittzahl = definierte Breite des ges. Wegs. 
  while (!NullSensor) {
    stepLeft(1); 
    if (--safetyCount <=0)  return false;
  }
  position = 0; 
  return true;
}

void stepLeft(int steps)
{
  for(;steps--;)
  {
    for (int s=0; s<8; s++)
    {
      for (int i=0; i<3; i++)
        digitalWrite(StepperIndex[i],StepperVal[s][i]);
      delay(StepperDelay);
    } 
  }
  // Wir sind da, Strom abschalten
  digitalWrite(StepperAPin,0);
  digitalWrite(StepperBPin,0);
  digitalWrite(StepperANegPin,0);
  digitalWrite(StepperBNegPin,0);
}

void stepRight(int steps)
{
  for(;steps--;)
  {
    for (int s=8; s--; ) // von 7 bis 0
    {
      for (int i=0; i<3; i++)
        digitalWrite(StepperIndex[i],StepperVal[s][i]);
      delay(StepperDelay);
    } 
  }
  // Wir sind da, Strom abschalten
  digitalWrite(StepperAPin,0);
  digitalWrite(StepperBPin,0);
  digitalWrite(StepperANegPin,0);
  digitalWrite(StepperBNegPin,0);
}

boolean setPosition(int x) {
  if (position < 0)
  {
    if (!zeroMotor()) return false; // Schief gegangene Nullstellung führt zum Abbruch
    position = 0; 
  }
  if (x > position) 
    stepRight(x-position); 
  else 
    stepLeft(position-x);
}



//function init

void setup()
{
  position = -1; //sicher ist sicher
  pinMode (StepperAPin, OUTPUT);
  pinMode (StepperBPin, OUTPUT);
  pinMode (StepperANegPin, OUTPUT);
  pinMode (StepperBNegPin, OUTPUT);
  pinMode (StepperLED, INPUT); // Eingang Gabellichtschranke... 
  digitalWrite (StepperLED, HIGH); // Pullup für Gabellichtschranke einschalten
  Serial.begin(9600);
  Serial.println("Schrittmotor bereit - zu welcher Position soll ich gehen?") ;
}

void loop()
{
  stepLeft(10);
  delay(1000);
  stepRight(10);
  delay(1500);
}



