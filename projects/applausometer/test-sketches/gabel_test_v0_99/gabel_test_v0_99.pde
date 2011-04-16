// Ansteuercode für Applausometer-Mikrofon
// April 2011 untergeek / abrowdi
// V0.99, 13. April 2011

// Das Mikro ist ein hundsordinäres Elektret-Kapselmikro
// mit einem simplen TL072 als Vorverstärker. 

// Konstanten -- aus dem Schrittmotorcode übernommen

// Die beiden Pole der Spule A
const int StepperAPin = 8; 
const int StepperANegPin = 7;
// Die beiden Pole der Spule B
const int StepperBPin = 4;
const int StepperBNegPin = 2; 

// LED der Gabellichtschranke. Wird ein- und ausgeschaltet, um eine ggf. Differenz messen zu können.
const int StepperLED = 3;
const int StartButton = 5; // Eingang
const int TriacOut= 6 ; // Ausgang, um die Lampen zu schalten. PWM = Dimmer für Phasenanschnittsteuerung.

// Eingang für die Gabellichtschranke
// Achtung, hier ist ein Analogeingang gemeint!
const int StepperNullSensor = 0;
// Mikroeingang (nach Vorverstärker
const int MicInput = 1;

boolean lsstate = false;

// Jetzt kann's losgehen. 

void meter(boolean i)
// Gibt einen 10-Bit-Wert als Sternchenreihe aus (div 32)
{
  if (i) 
    if (lsstate != i) {
      Serial.println("*");
      lsstate = i;
    }
  else
    if (lsstate != i) {
      Serial.println("-");
      lsstate = i;
    }
}

//function init

void setup()
{
  pinMode(StepperLED,INPUT);
  digitalWrite(StepperLED,HIGH);
  Serial.begin(9600);
  Serial.println("Schrittmotor bereit - zu welcher Position soll ich gehen?") ;
}

void loop()
{
  delay(1000);
  Serial.println(digitalRead(StepperLED));
  //meter(digitalRead(StepperLED));
}



