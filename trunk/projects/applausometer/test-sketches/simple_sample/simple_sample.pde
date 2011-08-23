#include <fix_fft.h>
#define TEST 1

const int dd = 64; 
const int dd2 = 128; 

// bestimmt die Anzahl der FFT-Frequenzb√§nder und damit
// alles andere: Samplezahl, Speicherverbrauch etc.

byte data[dd2];    // Speicher f√ºr gesampelte Daten und FFT-Ergebnis (Realteil)
byte im[dd2];      // Komplexe Zahlen bei der FFT: hier der Imagin√§rteil f√ºr Berechnung
int i=0,val;


void dirtySample(int prescale, byte dcOffset)
// Original-Sampleroutine des Urhebers; scheint mit ca. 32k zu sampeln.
// Leicht modifiziert:
// Prescale (0..3) als Bereichsumschaltung, um Quasi-11bit-Dynamikbereich zu erreichen:
// Prescale > 2 setzt den Referenz-Wert für den Analogeingang auf 5V, ansonsten 1.1V
// 
// DC Offset wird beim Samplen berücksichtigt. 
{
  int ii;
  int offset=128 - dcOffset;
  if (prescale > 2) {
      analogReference(DEFAULT);   //  Default (5v) aref voltage.
      prescale = 2;
  } else
      analogReference(INTERNAL); 

  for (ii=0; ii < dd2; ii++){                                     // We don't go for clean timing here, it's
      val = analogRead(0);                                      // better to get somewhat dirty data fast
      data[ii] = (val >> prescale) - offset;                            // than to get data that's lab-accurate
      im[ii] = 0;                                                       // but too slow, for this application.
      };
}

int rms8(byte d[], int n)
// Simple, auf Geschwindigkeit optimierte Bibliothek, die das quadratische Mittel bildet.
{
  int ii, sum = 0;
  for (ii=0; ii < n; ii++) {
    sum += (d[ii] * d[ii]) / n;   // Quadrat gleich durch n teilen, um im int-Bereich zu bleiben 
  }
  return int (sqrt(sum));
}


const byte hheight = 16;        //H√∂he des Histogramms
const byte hdiv = 128/hheight;  //Divisor (erleichtert dem Compiler die Optimierung

void histogram(byte d[])
{
   byte yy, xx, div;
   Serial.write(12);         //FF byteacter - vielleicht verstehts der Serial Monitor
   Serial.println("+---HISTOGRAM---->");
   for (yy = hheight; yy > 0; yy--) {
     div = (yy-1) * hdiv;
     for (xx=0; xx < dd; xx++) {
       if (d[xx] > div) 
        Serial.print('*'); else
        Serial.print('.');
     }
     Serial.println(" ");
   }
/*   Serial.print("RMS simple sample: ");
   Serial.println(rms8(data,dd));
   for (xx=0; xx < dd; xx++) { 
     Serial.print(int(d[xx])) ;
     Serial.print(", "); 
   }
     */ 
}
      
void setup()
    {   
    pinMode(13,OUTPUT);        // Pin für den Heartbeat
    pinMode(12,INPUT);          // Pin für den Taster
    digitalWrite(12,HIGH);       // Pullup aktivieren
    Serial.begin(9600);      // unter Linux bekomme ich die Sendegeschwindigkeit nicht umgestellt
    };
    
    //Taster eingebaut: Ein auf der Seriellen sendender Arduino bringt
    //alles durcheinander. Deshalb arbeitet die Routine nur, solange
    //ein Taster die Leitung 12 auf Null zieht. 
    
void loop() {
  while (digitalRead(12) == 0) {
    digitalWrite( 13, HIGH );
    dirtySample(0,0);              //liest 128 8-Bit-Werte ein.
#ifdef TEST
   for (i=0; i < dd2; i++) { 
     Serial.print(int(data[i])) ;
     if ((i % 16) == 15) Serial.println(); else Serial.print(", ");
   } 
#endif
   Serial.print("Quadrierter Mittelwert Samples ");
   Serial.println(rms8(data,dd2));
   fix_fft(data,im,7,0);   
    for (i=0; i< dd;i++){                                  
      data[i] = sqrt(data[i] * data[i] + im[i] * im[i]);  // Real- und Imagin√§rteil aufsummieren

      }; 
    histogram(data);
    Serial.println();
    Serial.print("Quadrierter Mittelwert FFT ");
    Serial.println(rms8(data,dd));
    digitalWrite( 13, LOW );
    delay(500);
    };
};
