/*
$Id$

MAKEfurt Applausometer
Code vom untergeek und vom byteborg
DAC und FFT von Didier Longueville (Arduinoos)

TODO:
- Analog-Input-Lautstärkemeter an den Analog-In anbasteln

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

*/

#include <Bounce.h>
#include <PlainDAC.h>
#include <PlainFFT.h>

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
#define ANPIN A1

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
#define MAINDELAY 100 /* ms */
uint8_t slen = 0;
#define SMAX 100 /* wie oft messen */
uint8_t peak = 0;
PlainDAC DAC = PlainDAC();
PlainFFT FFT = PlainFFT();
/* Acquisition parameters */
const uint16_t channel = ANPIN; /* Set default channel value */
const uint16_t samplingFrequency = 8000; /* Set default sampling frequency value */
const uint8_t acqMode = DAC_ACQ_MOD_DOUBLE; /* Set default acquisition mode value */
const uint16_t samples = 128; /* Set default samples value */
const uint8_t vRef = DAC_REF_VOL_DEFAULT; /* Set default voltage reference value */
/* Reference spectrum */
uint8_t vRefSpectrum[(samples >> 1)];
uint8_t vActSpectrum[(samples >> 1)];
uint8_t threshold = 5;
//uint8_t targetMatch = 50;



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
 *** Audio Input Software-only Ansatz mit FFT
 ***/

// Sample Buffer per A/D befüllen, FFT machen und ablegen
void getSpectrum(void) {
	/* Initialize data vector */
	uint8_t *vData = (uint8_t*)malloc(samples * sizeof(double)); 
	/* Acquire data in bytes array */
	DAC.AcquireData(vData, channel); 
	/* Reallocate memory space to doubles array for real values */
	double *vReal = (double*)realloc(vData, samples * sizeof(double)); 
	/* Adjust signal level */
	for (uint16_t i = 0; i < samples; i++) {
		vReal[i] = (((vReal[i] * 5.0) / 1024.0) - 2.5);
	}
	/* Allocate memory space to doubles array for imaginary values (all 0ed) */
	double *vImag = (double*)calloc(samples, sizeof(double)); 
	/* Weigh data */
	FFT.Windowing(vReal, samples, FFT_WIN_TYP_HAMMING, FFT_FORWARD); 
	/* Compute FFT */
	FFT.Compute(vReal, vImag, samples, FFT_FORWARD); 
	/* Compute magnitudes */
	FFT.ComplexToMagnitude(vReal, vImag, samples);
	/* Find max value */
	double max = 0;
	for (uint16_t i = 1; i < ((samples >> 1) - 1); i++) {
		if (vReal[i] > max) max = vReal[i];
	}
	/* Clean, normalize and store data in actual spectrum */
	for (uint16_t i = 1; i < ((samples >> 1) - 1); i++) {
		if ((vReal[i-1] < vReal[i]) && (vReal[i] > vReal[i+1]) 
                    && (uint8_t(vReal[i] * 100.0 / max) > threshold)) {
			vActSpectrum[i] = uint8_t((vReal[i] * 255.0) / max);
		}
		else {
			vActSpectrum[i] = 0;
		}
	}
	/* Release memory space */
	free(vReal);
	free(vImag);	
}

// Aus dem letzten gemessenen Spektrum ein Referenzspektrum machen
void setRefSpectrum(void) {
/* Copy actual spectrum in ref spectrum */
	for (uint16_t i = 1; i < ((samples >> 1) - 1); i++) {
		vRefSpectrum[i] = vActSpectrum[i];
	}
}

void printSpectrum(uint8_t *vSpectrum) {
/* For diagnostics purposes */
	for (uint16_t i = 0; i < (samples >> 1); i++) {
		Serial.print(((i * 1.0 * samplingFrequency) / samples), 2);
		Serial.print(" ");
		Serial.print(vSpectrum[i], DEC);
		Serial.println();	
	}
}

uint8_t matchSpectra(void) {
/* Compute the match criteria between the reference spectrum and the actual spectrum 
	 The result is expressed in percent and ranges strictly from 0% to 100% */
	uint16_t sumOfRefOrAct = 0;
	uint16_t sumOfAbsDiff = 0;
	for (uint16_t i = 1; i < ((samples >> 1) - 1); i++) {
		/* Compute absolute differences between reference and actual spectra */
		uint8_t diff;
		if (vRefSpectrum[i] > vActSpectrum[i]){
			diff = (vRefSpectrum[i] - vActSpectrum[i]);
			sumOfRefOrAct += vRefSpectrum[i];
		}
		else if (vActSpectrum[i] > vRefSpectrum[i]){
			diff = (vActSpectrum[i] - vRefSpectrum[i]);
			sumOfRefOrAct += vActSpectrum[i];			
		} 
		else {
			diff = 0;
			sumOfRefOrAct += vRefSpectrum[i];
		}
		sumOfAbsDiff += diff;
	}

	if (sumOfRefOrAct != 0x00) {
		/* Returns the matching value in pct */
		return(uint8_t(((sumOfRefOrAct - sumOfAbsDiff) * 100.0) / sumOfRefOrAct));
	}
	else {
		/* Reference spectrum not set */
		return(0x00);
	}
}


/***
 *** Arduino initialisieren
 ***/

void setup()
{
  Serial.begin(115200);
  Serial.print("ATZ0");
  // hearteat init
  pinMode(HEARTBEAT, OUTPUT);
  digitalWrite(HEARTBEAT, LOW);
  // lichtschranke init
  Serial.print(".");
  pinMode (GATE_END, INPUT);
  digitalWrite (GATE_END, HIGH);
  // button init
  Serial.print(".");
  pinMode(BUTTON_START, INPUT);
  digitalWrite(BUTTON_START, HIGH);
  // stepper init
  Serial.print(".");
  pinMode (STEP_AP, OUTPUT);
  pinMode (STEP_BP, OUTPUT);
  pinMode (STEP_AN, OUTPUT);
  pinMode (STEP_BN, OUTPUT);
  zeroStepper();
  // DAC init
  Serial.print(".");
  DAC.SetAcquisitionParameters(samplingFrequency, samples, acqMode, vRef);
  DAC.StartAcquisitionEngine();	
  Serial.println(" OK");
}


/***
 *** Arduino laufen lassen (main loop)
 ***/
  uint8_t runstate = 0; // Laufzeit Statusvariable
  uint8_t tmp = 0;

void loop() {
  heartBeat(); // blinken
    
  if (button.update()) { // knopp auslesen
    if (button.fallingEdge()) { // knopp gedrückt
      if (runstate == 0) { // 0: standby -> 1: messen
        runstate = 1; // nächstes: messung
            Serial.print("Button");
      } 
    } // knopp gedrückt
  } // knopp auslesen

  // Audio
  getSpectrum();
  
  if (runstate == 0) { // 0: standby
    setRefSpectrum();
    slen = 0;
    peak = 0;
  } 
  else if (runstate == 1) { // 1: messen
    tmp = matchSpectra();
    Serial.println((int)tmp);
    if (tmp > peak) {
      peak = tmp;
    }
    if (slen > SMAX) { // Ende Messung wenn max. Anzahl messungen erreicht
      runstate = 2;
    }
    slen++;
  } 
  else if (runstate == 2) { // 2: ausgeben
    //stepAbsolute(finishSampling());
    Serial.print("PK: ");
    Serial.print((int)peak);
    runstate = 0; // stop
  }
    
  //delay(MAINDELAY);
}



