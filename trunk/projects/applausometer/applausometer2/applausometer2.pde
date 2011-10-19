/*

MAKEfurt Applausometer
Code vom untergeek und vom byteborg

Verwendet eine überarbeitete 8Bit-FFT-Routine von deif (siehe fix_fft.h)
Angeregt vom FFT-Analyser von Paul Bishop (http://blurtime.blogspot.com/2010/11/arduino-realtime-audio-spectrum.html)


TODO:

(IRGENDWAS IST DA NOCH FAUL!)

- "Highscore" ab dem 2. Applaus
- Auto-Rücklauf der Skala nach einer Zeit. 
- Befehle über serielle Schnittstelle entgegennehmen. 

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

#define TEST2

#include <Bounce.h>
#include <TimerOne.h>     // Library für Interruptroutinen
#include <fix_fft.h>      // Festkomma-8Bit-FFT-Routinen

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

// time constants
#define MAIN_DELAY 500    // wait .5s before heartbeat
#define FRAME_DELAY 1000  // measure every 1s
#define RESULT_DELAY 10000 // Time before switching LAMP out and resetting applausometer

#define SAMPLE_PERIOD 160  // 160 Mikrosekunden pro Zyklus beim Samplen = 6,4 kHz. Schneller macht's der Arduino-ADC nicht. 

// Hier die Definitionen für die Filter-Funktionen:
// Bei 6,4kHz Sample-Frequenz und 64 Bändern steht jedes Band für 50Hz. 

#define APPLAUSE_LO_BAND 20    // entspricht 1kHz
#define APPLAUSE_HI_BAND 64    // bis zur maximal analysierbaren Frequenz von 3,2kHz
#define APPLAUSE_LEVEL 40     // Unterhalb dieser Amplitude gibt's keinen Applaus.
#define APPLAUSE_THRESHOLD 20

#define SCALE_APPLAUSE 2      // Prescale applausSum => Applausometer-Skala

// Hier etwas experimentelles Wissen über Beifall: 
// Beifall ist relativ breitbandig (was Wunder), geht in Richtung rosa Rauschen - 
// und hat seine Peak-Frequenzen zwischen 1-2 kHz.
// Sprache hingegen findet vor allem im Frequenzband unter 1kHz statt (das Telefon überträgt zwischen 300Hz und 3kHz).
// 
// Conclusio: 
// Zur deutlicheren Abgrenzung von Raumgeräuschen und Applaus wird jeweils ein Filter angewandt
// - Ein Sprachfilter schaltet alle Frequenzen oberhalb von 1,5kHz aus - zur Erkennung reicht das.
// - Ein Applausfilter hat einen vorgeschalteten Hochpass ab 1kHz.



const int dm = 7;           // Größe der Datenfelder 2**dm
const int M_HALF = 1 << (dm-1); // 2**dm-1 = 64 
const int M = 1 << dm;    // 2**7 = 128

// bestimmt die Anzahl der FFT-Frequenzb√§nder und damit
// alles andere: Samplezahl, Speicherverbrauch etc.

int * data; // Speicher für alles Wesentliche. Benötigt einen altmodischen MALLOC-Aufruf.
char * rd;    // Speicher für gesampelte Daten und FFT-Ergebnis (Realteil)
char * id;      // Imaginärteil: FFT wird auf komplexe Zahlen angewandt, deshalb nötig. Beim Samplen = 0.
int i,j,dcoffset,volume,amplitude;

long applausSum; 

volatile int sample;   // Variable zur Übergabe der via Interrupt gesampelten Werte



void return1Sample(void)
// Diese Routine wird in den Interrupt eingehängt, wenn gesampled wird. 
// Achtung: Laut Arduino-Doku benötigt ein analogRead() etwa 100uS - was unterhalb der laut AVR-Datenbuch etwa bei
// max. 15kHz liegt. Experimentell hat sich erwiesen, dass bereits 12,8kHz Sample-Frequenz mit analogRead() zuviel sind - 
// schade, wär' so schön gewesen. Also hören wir bei 6,8kHz Sample-Frequenz auf - die Nyman-Frequenz, also die gerade noch
// messbare höchste Freqenz liegt also bei schnöden 3,2 kHz. Für Applaus reicht das aber allemal. 
{
  sample = analogRead(ANPIN);
}

int cleanSample(int * d, int n)
// Sauberes Timing mit den Interrupt-Routinen.
// Sie sammelt unsignierte 10Bit-Werte - mit denen sampleProcess() dann alles Mögliche anstellt.

// Sampelt n Integer-Werte an die vom Pointer übergebene Adresse. 

// Routine berechnet beim Samplen den Mittelwert der gesampelten Werte und gibt ihn zurück 
// Dieser Wert ist in der Folge für die Berechnung der Null-Linie wichtig
{
  long sum;
  #ifdef TEST
  long timestamp = micros();
  #endif
  int ii;         
  sum = 0; 
  Timer1.attachInterrupt(return1Sample,SAMPLE_PERIOD);   // Los geht's.
  for (ii=0; ii < n; ii++) { 
    sample = -1;     // Nicht vergessen: Flag wieder löschen!
    while (sample == -1) { /* wait */ };    // Auf Sample warten. Wenn Interrupt nicht eingehängt, warten wir ewig. 
    d[ii] = sample;   // Vorzeichenlose 8-Bit-Werte lesen
    sum += sample;
  }
  #ifdef TEST
  timestamp = micros()-timestamp;
  Serial.println();
  Serial.print("Sample routine in us:");
  Serial.println(timestamp); 
  #endif
  Timer1.stop();     // Timer wieder anhalten. 
  return sum / n ;         // Mittelwert der Samples; braucht man zum Normalisieren. 
}


int sampleProcess(int * d, char * dr, char * di)
// Zieht Daten; sucht die Nulllinie; berechnet die Amplitude und daraus die nötige Verstärkung.
//
// Ziel sind vorzeichenbehaftete 8-Bit-Daten.
//
// Diese Daten werden in zwei char-Arrays abgelegt, die das Eingangsarray überschreiben: 
// - ab &d[0] werden die vorzeichenbehafteten Real-Daten abgelegt
// - ab &d[n/2] werden Nullen geschrieben - das entspricht dem späteren Imaginärteil für die FFT-Berechnung

// Wenn nicht der volle Dynamikbereich genutzt wird, schaltet sie den Arduino auf interne AD-Referenz und
// versucht, mit diesem "Vorverstärker" zu sinnvollen 8-Bit-Daten zu kommen. 

// Die folgende Konstante ist die Schwelle, unterhalb derer die Amplitude liegen muss, um ein nochmaliges Samplen mit
// erhöhter Verstärkung auszulösen. 

#define LO_DYN  16
{
  int ii, tmp, offset, prescale, volume;
  long sum;
// "Normale" Vorverstärkung: Interne 5V-Referenz.
  analogReference(DEFAULT);
  offset = cleanSample(d,M);
  sum = 0;
  for (ii=0; ii < M; ii++) {
    tmp = d[ii] - offset;            // auf DC-Offset - ab jetzt haben wir vorzeichenbehaftete Werte
#ifdef TEST
   Serial.print(tmp);
   if (ii % 32 == 31) Serial.println(); else Serial.print(", ");
#endif
    sum += (long) tmp * (long) tmp;    // Berechnung des quadratischen Mittels für die Amplitudenabschätzung
    };
// Dynamikbereich anpassen, auf 8 Bit normalisieren
// Wenn nötig, drehen wir sogar die Vorverstärkung hoch. 
// Das passiert aufgrund einer angreifbaren mathematischen Annahme: 
// Für eine Sinuswelle beträgt der QMW rund 71% der Amplitude - also wird j um diesen Wert korrigiert.
   amplitude = (sqrt(sum / M) * 100) / 71;             // Quadratisches Mittel - in etwa 70,7% der Amplitude
#ifdef TEST
       Serial.println();
       Serial.println(offset);
       Serial.println(sum);
       Serial.println(sum / M);
       Serial.print("Berechne Amplitude mit ");
       Serial.println(amplitude,DEC);
#endif
   if (tmp < LO_DYN) {
     analogReference(INTERNAL);         // Referenzspannung für Sampling auf 1.1V
     offset = cleanSample(d,M);         // nochmal samplen
     prescale = 0;
     volume = 1;  
   } else if (tmp < 128) {              // Amplitude im 8Bit-Bereich? (Werte -128...127)
   prescale = 0;                        // Kein Divisor nötig, aber nicht nochmal samplen
   volume = 2; 
     } else if (tmp < 256) {              // Amplitude im 9-Bit-Bereich? (Werte -256...255)
        prescale = 1;                    // Divisor 2 (also um 1 bit schieben)
       volume = 4; } else {
         volume = 8;
         prescale = 2; 
       }
       #ifdef TEST
       Serial.println();
       Serial.print("Setze Volume auf ");
       Serial.println(volume,DEC);
       #endif
    for (ii=0; ii < M; ii++) {
      tmp = (d[ii] - offset) >> prescale;
      if (tmp > 127) tmp = 127;        // clippen auf 8 Bit mit Vorzeichen
        else if (tmp < -128) tmp = -128; 
// Bei der außerordentlich grobschlächtigen 8-Bit-Arithmetik muss man damit rechnen, dass dieser Algorithmus 
// des öfteren mal clippt - sprich: zusätzliche Verzerrungen einführt. Aber wir bauen ja hier kein Analyse-Tool,
// sondern einen simplen Filter. Also: egal.
      rd[ii] = char(tmp);            // Achtung: Originalwerte in d[] werden überschrieben!
                                     // Weshalb es auch keine gute Idee ist, jetzt schon die Imaginärdaten zu schreiben...
                                     // ...das löscht die zweite Hälfte der Samples. 
     
    }    
// Den Imaginärteil nicht vergessen und durchgängig auf 0 setzen    
   for (ii=0; ii < M; ii++) id[ii] = 0;
#ifdef TEST
   histogram(rd,M);
#endif
// Hier ganz wildes C: Ein Quasi-Rückgabewert - Routine setzt eine public-Variable.
// Später löschen; dient nur dem Debugging.
  dcoffset = offset;

//Rückgabewert: Die Verstärkung - gespeichert in volume    
  return volume;  
}

int isApplause()
{
   int ii;
   long sum = 0;
   volume = sampleProcess(data, rd, id);
   if (amplitude < APPLAUSE_LEVEL) return 0;      // Wenn's zu leise ist: kein Applaus.  
   fft_windowing(rd,dm);              // Einfache Windowing-Funktion (von Hann / "raised-cosine"), um FFT-Fehler zu dämpfen
   fix_fft(rd,id,dm,0);               // Parameter: rd und id sind die char-Arrays mit den Daten, 
                                      // dm ist die Bit-Anzahl der Sample-Breite M. 
histogram(rd,M_HALF);
   for (ii = APPLAUSE_LO_BAND; ii < APPLAUSE_HI_BAND; ii++) 
     sum += (long) rd[ii] * (long) rd[ii];
   sum = sqrt(sum / (APPLAUSE_HI_BAND - APPLAUSE_LO_BAND)) * volume; 
   return sum;
}


const char hheight = 16;        //H√∂he des Histogramms
const char hdiv = 128/hheight;  //Divisor (erleichtert dem Compiler die Optimierung

void histogram(char d[], int n)

#define SCHMAL 130
{
  
   int yy, xx, div;
   Serial.write(12);         //FF character - vielleicht verstehts der Serial Monitor
   Serial.println("+---HISTOGRAM---->");
   for (yy = hheight; yy > 0; yy--) {
     div = (yy-1) * hdiv + (hdiv / 2);
   if (n > SCHMAL) {

     /* Dieser Code quetscht zwei Werte in eine Spalte - aber wir haben genug Platz, also aufheben und weg: */

    for (xx=0; xx < n; xx+=2) {    // Eine Histogrammsäule enthält sozusagen 2 Spalten.
       if (d[xx] > div) { 
         if (d[xx+1] > div)   
            Serial.print('#'); else    // Wenn linke und rechte Spalte leuchten
            Serial.print('['); }
          else if (d[xx+1] > div) 
            Serial.print(']'); else
            Serial.print('.');
     }
   } else { 
    for (xx=0; xx < n; xx++) {    // Ganz normale Histogrammsäule. 
     if (d[xx] > div)     
          Serial.print('*'); else    // Wenn linke und rechte Spalte leuchten
          Serial.print('.');
     }
   } 
     Serial.println(" ");
   }
}

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



// Heartbeat State
static byte hbstate = LOW;

// Sampling Setup & Buffer
#define MAINDELAY 100 /* ms */
#define SMAX 100 /* wie oft messen */
uint8_t peak = 0;
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
  // Zur Begrüßung mal kurz das Licht anmachen
  pinMode(LAMP, OUTPUT);
  digitalWrite(LAMP, HIGH);
  delay(500);             
  digitalWrite(LAMP, LOW);
  // stepper init
  Serial.print(".");
  pinMode (STEP_AP, OUTPUT);
  pinMode (STEP_BP, OUTPUT);
  pinMode (STEP_AN, OUTPUT);
  pinMode (STEP_BN, OUTPUT);
  zeroStepper();
  // DAC init
  Serial.print(".");
  data = (int *) malloc(2*M);  // Gib Speicher! 2 Byte je Wert - M Worte Samplespeicher werden gebraucht. 
  rd = (char *) data;
  id = (char *) data+M;
    
  Timer1.initialize(SAMPLE_PERIOD);   // 160 us pro Zyklus, also: 6,4 kHz. Ergibt bei 128 Samples genau 64 x 50Hz breite Bänder.
  Timer1.stop();                      // das überlass mal der Routine clearSample
  Serial.println(" OK");
}


/***
 *** Arduino laufen lassen (main loop)
 ***/
  uint8_t runstate = 0; // Laufzeit Statusvariable
  int tmp = 0;
  int tmp2 = 0;
  int time = 0; 

void loop() {
  heartBeat(); // blinken
    
  if (button.update()) { // knopp auslesen
    if (button.fallingEdge()) { // knopp gedrückt
      if (runstate == 0) { // 0: standby -> 1: messen
        runstate = 1; // nächstes: messung
        digitalWrite(LAMP, HIGH);
            Serial.print("Button");
      } 
    } // knopp gedrückt
  } // knopp auslesen

  if (runstate == 0) { // 0: standby
   volume = sampleProcess(data, rd, id);
   Serial.println(amplitude); 
//   fft_windowing(rd,dm);              // Einfache Windowing-Funktion (von Hann / "raised-cosine"), um FFT-Fehler zu dämpfen
//   fix_fft(rd,id,dm,0);               // Parameter: rd und id sind die char-Arrays mit den Daten,
//   histogram(rd,M_HALF); 
    delay(MAIN_DELAY); 
  } 
  else if (runstate == 1) { // 1: messen; Applausometer ist scharf
  
    Serial.println();
    Serial.println("WAITING FOR APPLAUSE TO COMMENCE");
    tmp = 0;
    while (tmp <= APPLAUSE_THRESHOLD) { // warte auf Applaus
      tmp = isApplause();
      Serial.print(amplitude,DEC);
      Serial.print("  -");
      Serial.println(tmp,DEC);
    }
    Serial.println("APPLAUSE DETECTED, START MEASUREMENT");
    Serial.print("INITIAL LEVEL ");
    Serial.println(tmp,DEC);
    histogram(rd,M_HALF);
    applausSum = 0;
    do {
      heartBeat();
      tmp2 = millis();
      tmp = isApplause();
      Serial.print("(t = ");
      Serial.print(time,DEC);
      Serial.print(") lvl = ");
      Serial.println(tmp,DEC);
      stepRelative (-(tmp / SCALE_APPLAUSE));
      applausSum += tmp / SCALE_APPLAUSE;     // nicht zu groß werden lassen
      while ((millis() - tmp2) < FRAME_DELAY) ; // 1 Zyklus abwarten
      time++;   
    } while (tmp > 0) ;
    Serial.println();
    Serial.print("END APPLAUSE - total ");
    Serial.print(applausSum,DEC);
    Serial.print(" in ");
    Serial.print(time,DEC);
    Serial.println("s ");
    // Licht ist aus, zurück auf Null, dann Licht an und auf Max-Wert warten.
    digitalWrite(LAMP, LOW);
    zeroStepper();
    digitalWrite(LAMP, HIGH);
    stepAbsolute(applausSum);
    delay(RESULT_DELAY);
   // Die Show ist vorbei, warte auf den nächsten Vortrag.  
    digitalWrite(LAMP, HIGH);
    zeroStepper();
    runstate = 0; // stop
  }
    
//  delay(MAIN_DELAY);
}



