#include <fix_fft.h>
#define TEST 1
#define BUTTON 12

const int dm = 8;           // Größe der Datenfelder 2**dm
const int M_HALF = 1 << (dm-1); // 2**dm-1 = 128 
const int M = 1 << dm;    // 2**8 = 256

// bestimmt die Anzahl der FFT-Frequenzb√§nder und damit
// alles andere: Samplezahl, Speicherverbrauch etc.

int * data; // Speicher für alles Wesentliche. Spart einen MALLOC-Aufruf.
char * rd;    // Speicher für gesampelte Daten und FFT-Ergebnis (Realteil)
char * id;      // Imaginärteil: FFT wird auf komplexe Zahlen angewandt, deshalb nötig. Beim Samplen = 0.
int i,j,dcoffset,volume;


int dirtySample(int * d, int n)
// Wie die Original-8Bit-Sampleroutine samplet sie einfach munter drauflos, ohne sich ums Timing zu kümmern.
// Sie sammelt unsignierte 10Bit-Werte - mit denen sampleProcess() dann alles Mögliche anstellt.

// Routine berechnet beim Samplen den Mittelwert der gesampelten Werte und gibt ihn zurück 
// Dieser Wert ist in der Folge für die Berechnung der Null-Linie wichtig
{
  long sum = 0;
  int ii;         
// Okay: sauber ist das nicht - auch nicht sauber getimed. Sampelt mit etwa 32kHz - später durch sauberes Sampling mit,
// sagen wir mal, 10kHz ersetzen. 
  for (ii=0; ii < n; ii++) { 
    d[ii] = analogRead(0);   // Vorzeichenlose 8-Bit-Werte lesen
    sum += d[ii] ;
  }
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

#define LO_DYN  10
{
  int ii, tmp, offset, prescale, volume;
  long sum = 0;
// "Normale" Vorverstärkung: Interne 5V-Referenz.
  analogReference(DEFAULT);
  offset = dirtySample(d,M);
  for (ii=0; ii < M; ii++) {
    tmp = d[ii] - offset;            // auf DC-Offset - ab jetzt haben wir vorzeichenbehaftete Werte
    sum += tmp * tmp;               // Berechnung des quadratischen Mittels für die Amplitudenabschätzung
#ifdef TEST
      Serial.print(tmp,DEC);
      Serial.print(",  ");
      if ((ii % 16) == 15) Serial.println();
#endif
    };
// Dynamikbereich anpassen, auf 8 Bit normalisieren
// Wenn nötig, drehen wir sogar die Vorverstärkung hoch. 
// Das passiert aufgrund einer angreifbaren mathematischen Annahme: 
// Für eine Sinuswelle beträgt der QMW rund 71% der Amplitude - also wird j um diesen Wert korrigiert.
   volume = 8;
   tmp = (sqrt(sum / M) * 100) / 71;             // Quadratisches Mittel - in etwa 70,7% der Amplitude
#ifdef TEST
       Serial.println();
       Serial.println(sum);
       Serial.println(sum / M);
       Serial.print("Berechne Amplitude mit ");
       Serial.println(tmp,DEC);
#endif
   if (tmp < LO_DYN) {
     analogReference(INTERNAL);         // Referenzspannung für Sampling auf 1.1V
     offset = dirtySample(d,M);         // nochmal samplen
     prescale = 0;
     volume = 1;  
   } else if (tmp < 64) {              // Amplitude im 8Bit-Bereich? (Werte -128...127)
   prescale = 0;                        // Kein Divisor nötig, aber nicht nochmal samplen
   volume = 2; 
     } else if (tmp < 128) {              // Amplitude im 9-Bit-Bereich? (Werte -256...255)
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

#ifdef TEST
      Serial.print(tmp,DEC);
      Serial.print(",  ");
      if ((ii % 16) == 15) Serial.println();
#endif
      
    }    
// Den Imaginärteil nicht vergessen und durchgängig auf 0 setzen    
    for (ii=0; ii < M; ii++) id[ii] = 0;
// Hier ganz wildes C: Ein Quasi-Rückgabewert - Routine setzt eine public-Variable.
// Später löschen; dient nur dem Debugging.
  dcoffset = offset;

//Rückgabewert: Die Verstärkung - gespeichert in volume    
  return volume;  
}

// Hier etwas experimentelles Wissen über Beifall: 
// Beifall ist relativ breitbandig (was Wunder), geht in Richtung rosa Rauschen - 
// und hat seine Peak-Frequenzen zwischen 1-2 kHz.
// Sprache hingegen findet vor allem im Frequenzband unter 1kHz statt (das Telefon überträgt zwischen 300Hz und 3kHz).
// 
// Conclusio: 
// Zur deutlicheren Abgrenzung von Raumgeräuschen und Applaus wird jeweils ein Filter angewandt
// - Ein Sprachfilter schaltet alle Frequenzen oberhalb von 1,5kHz aus - zur Erkennung reicht das.
// - Ein Applausfilter hat einen vorgeschalteten Hochpass ab 1kHz. 

int rms8(char d[], int n)
// Simple, optimierte Routine, die das quadratische Mittel bildet.
{
  long sum = 0; 
  int ii, j;
  for (ii=0; ii < n; ii++) {
    j = int(d[ii]) ; 
    sum += (j * j); 
  }
  return int (sqrt(sum / n));
}


const char hheight = 16;        //H√∂he des Histogramms
const char hdiv = 128/hheight;  //Divisor (erleichtert dem Compiler die Optimierung

void histogram(char d[])

#define SCHMAL 1
{
  
   int yy, xx, div;
   Serial.write(12);         //FF character - vielleicht verstehts der Serial Monitor
   Serial.println("+---HISTOGRAM---->");
   for (yy = hheight; yy > 0; yy--) {
     div = (yy-1) * hdiv;
     
     #ifdef SCHMAL
     /* Dieser Code quetscht zwei Werte in eine Spalte - aber wir haben genug Platz, also aufheben und weg: */

    for (xx=0; xx < M_HALF; xx++) {    // Eine Histogrammsäule enthält sozusagen 2 Spalten.
       if (d[xx] > div) { 
         if (d[xx+1] > div)   
            Serial.print('#'); else    // Wenn linke und rechte Spalte leuchten
            Serial.print('['); }
          else if (d[xx+1] > div) 
            Serial.print(']'); else
            Serial.print('.');
     } 
     #else
    for (xx=0; xx < M_HALF; xx++) {    // Eine Histogrammsäule enthält sozusagen 2 Spalten.
       if (d[xx] > div)     
            Serial.print('#'); else    // Wenn linke und rechte Spalte leuchten
            Serial.print('.');
     }
    #endif 
     Serial.println(" ");
   }
}
      
void setup()
    {   
    pinMode(13,OUTPUT);        // Pin für den Heartbeat
    pinMode(BUTTON,INPUT);          // Pin für den Taster
    digitalWrite(BUTTON,HIGH);       // Pullup aktivieren2
    Serial.begin(38400);      // unter Linux bekomme ich die Sendegeschwindigkeit nicht umgestellt
    data = (int *) malloc(2*M);  // Gib Speicher! 2 Byte je Wert - M Worte Samplespeicher werden gebraucht. 
    rd = (char *) data;
    id = (char *) data+M;
    };
    
    //Taster eingebaut: Ein auf der Seriellen sendender Arduino bringt
    //alles durcheinander. Deshalb arbeitet die Routine nur, solange
    //ein Taster die Leitung 12 auf Null zieht. 
    
void loop() {
  while (digitalRead(BUTTON) == 0) {
    digitalWrite( 13, HIGH );
// Jetzt einmal durchsamplen.
// SampleProcess() tut genau das: Samplen und die Samples dann aufbereiten.
// Heraus kommen die gesampelten Werte in rd[] und der Imaginärteil (nach dem Sampeln alle 0) in id[].
// Alles als signierte 8-Bit-Daten.
// Rückgabewert: Der Verstärkungsfaktor. (Wer sagt denn, dass wir uns mit 8 Bit zufrieden geben müssen... :) 
   volume = sampleProcess(data, rd, id);
   
#ifdef TEST
   j = 0;
   for (i=0; i < M; i++) { 
     j += int(data[i]); 
   }
  Serial.print("Mittelwert ");
   Serial.println(j / M);
   Serial.print("DC Offset ");
   Serial.println(dcoffset);
   Serial.print("Volume ");
   Serial.println(volume);
   
#endif
   Serial.print("Quadrierter Mittelwert Samples ");
   Serial.println(rms8(rd,M)*volume);   
// BTW: volume ist der Vorverstärker-Multiplikator. Eigentlich müsste man hier noch eine Umrechnung auf die logarithmische
// dB-Skala durchführen, aber: kommt Zeit, kommt Umrechnung. 
// So, jetzt haben wir Daten, es kann losgehen.    

   fft_windowing(rd,dm);              // Windowing-Funktion (von Hann / "raised-cosine"), um FFT-Fehler zu dämpfen
   fix_fft(rd,id,dm,0);               // Parameter: rd und id sind die char-Arrays mit den Daten, 
                                      // dm ist die Bit-Anzahl der Sample-Breite M. 
//
    for (i=0; i< M_HALF;i++){                                  
      rd[i] = sqrt(rd[i] * rd[i] + id[i] * id[i]);  // Real- und Imagin√§rteil aufsummieren

      }; 
    histogram(rd);
    data[0] = 0;                       // DC-Anteil herausrechnen
    Serial.println();
    Serial.print("Quadrierter Mittelwert FFT ");
    Serial.println(rms8(rd,M)*volume);
    digitalWrite( 13, LOW );
    delay(500);
    };
};
