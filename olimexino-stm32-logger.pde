#include <Ethernet.h>
#include <SdFat.h>
#include <SdFatUtil.h>

Sd2Card card;
SdVolume volume;
SdFile root;
SdFile file;


bool fileSystemNeedsInit = true;

int currentFileIndex = 0;
char logFileName[32];

char *sizeAsString(uint32_t sz)
{
    
    static char buf[16];
    if (sz > 1024*1024*1024)
        sprintf(buf, "%1.1f GB", sz/1024.0f/1024.0f/1024.0f);
    else
        if (sz > 1024*1024)
            sprintf(buf, "%1.1f MB", sz/1024.0f/1024.0f);
    else
        if (sz > 1024)
            sprintf(buf, "%1.1f KB", sz/1024.0f);
        else
           sprintf(buf, "%d B", sz);
    return buf;
}

void toggleLedYellow()
{
    static int toggleLed3 = 0;
    digitalWrite(3, toggleLed3);
    toggleLed3 = 1-toggleLed3;
}

void toggleLedGreen()
{
    static int toggleLed13 = 0;
    digitalWrite(13, toggleLed13);
    toggleLed13 = 1-toggleLed13;
}

void toggleAlert()
{
    static int toggleAlert = 0;
    digitalWrite(13, toggleAlert);
    digitalWrite(3, 1-toggleAlert);
    toggleAlert = 1-toggleAlert;
}

#define error(s) error_P(PSTR(s))

void error_P(const char* str) {
    PgmPrint("error: ");
    SerialPrintln_P(str);
    if (card.errorCode())
    {
        PgmPrint("SD error: ");
        SerialUSB.print(card.errorCode(), HEX);
        SerialUSB.print(',');
        SerialUSB.println(card.errorData(), HEX);
    }
    for (int i = 0; i < 100; i++)
    {
        toggleAlert();
        delay(100);
    }
}

#define MAXBUFFERS 20
#define BLOCKSIZE 512
uint8_t buffer[MAXBUFFERS][BLOCKSIZE];
uint16_t head=0;
uint8_t curBuffer = 0;
uint8_t lastBuffer = 0;
uint8_t unflashedBuffers = 0;


uint32_t nlCount = 0;
uint8_t nlCharacter = 0;

void serialEventISR() 
{
    while (Serial1.available()) 
    {
        uint8_t value = (uint8_t) Serial1.read();
        if ((!nlCharacter) && ((value == '\n') || (value == '\r')) )
        {
            nlCharacter = value;
        }
        if (value == nlCharacter)
        {
            nlCount++;
            toggleLedYellow();
        }
        buffer[curBuffer][head++] = value;
        if (head >= BLOCKSIZE)
        {
            head = 0;
            curBuffer++;
            unflashedBuffers++;
            if (curBuffer >= MAXBUFFERS)
                curBuffer = 0;
        }
    }
}


int count = 0;

/*
    TODO:
    find next free file
    write in folder
*/

void setupFileSystem()
{
    if (!fileSystemNeedsInit)
        return;
    if (!card.init(SPI_FULL_SPEED)) 
    {
        error("card.init failed");
    }
    if (!volume.init(&card)) 
    {
        error("volume.init failed");
    }
    if (!root.openRoot(&volume)) 
    {
        error("openRoot failed");
    }
    char outb[64];
    sprintf(outb, "blks/cluster: %u\nblks/fat: %lu", volume.blocksPerCluster(), volume.blocksPerFat());
    SerialUSB.println(outb);
    sprintf(outb, "total clusters: %lu", volume.clusterCount());
    SerialUSB.println(outb);
    sprintf(outb, "total size: %lu MB", volume.clusterCount()*volume.blocksPerCluster()*512/1024/1024);
    SerialUSB.println(outb);
    for (int i=0; i < 100; ++i)
    {
        sprintf(logFileName, "SERIAL%02d.LOG", i);
        if (file.open(&root, logFileName, O_READ))
        {
            
            sprintf(outb, "file %s size: %s", logFileName, sizeAsString(file.fileSize()));
            SerialUSB.println(outb);
            file.close();
            continue;
        }
        else
            break;
    }
    if (file.open(&root, logFileName, O_CREAT | O_WRITE | O_TRUNC))
    {
        file.close();
        SerialUSB.print(logFileName);
        SerialUSB.print(": created serial LogFile\n");
        fileSystemNeedsInit = false;
    }
    else
    {
        SerialUSB.print(logFileName);
        SerialUSB.print(": error creating LogFile\n");
    }
}

uint32_t nextAction = 0;



void setup()
{
    pinMode(13, OUTPUT);
    digitalWrite(13, 0);
    pinMode(3, OUTPUT);
    digitalWrite(3, 1);
    Serial1.begin(115200);
    Serial2.begin(115200);
    //delay(5000);
    SerialUSB.begin();
    Timer2.setChannel1Mode(TIMER_OUTPUTCOMPARE);
    Timer2.setPeriod(100); // in microseconds
    Timer2.setCompare1(1);      // overflow might be small
    Timer2.attachCompare1Interrupt(serialEventISR);
    nextAction = millis()+10000;
}


void DebugPrintBuffer()
{
    for (int i=0; i < BLOCKSIZE; ++i)
    {
        char outb[256];
        sprintf(outb, "%d:%02x %c\n", i, buffer[lastBuffer][i], buffer[lastBuffer][i]);
        SerialUSB.print(outb);
    }
}


int fileInfoCnt = 0;

void loop()
{
    //serialEventISR();
    delay(1);
    if (millis()>=nextAction || unflashedBuffers > MAXBUFFERS*3/4)
    {
        nextAction=millis()+10000;
        if (fileSystemNeedsInit)
        {
            setupFileSystem();
        }
        else
        {
            fileInfoCnt++;
            if (fileInfoCnt>=6)
            {
                fileInfoCnt = 0;
                 if (file.open(&root, logFileName, O_READ))
                 {
                     char outb[64];
                     size_t currentSize = file.fileSize();
                     sprintf(outb, "file %s size: %s", logFileName, sizeAsString(currentSize));
                     SerialUSB.println(outb);
                     file.close();
                     if (currentSize>=1024*1024*1024)
                         fileSystemNeedsInit = true;
                 }
            }
        }
        char outb[32];
        sprintf(outb, "nl: %ld  bf:%d  hd:%d\n", nlCount, curBuffer, head);
        SerialUSB.print(outb);
        if ((curBuffer!=lastBuffer) && !fileSystemNeedsInit)
        {
            toggleLedGreen();
            SerialUSB.print("appending to file: ");
            SerialUSB.println(logFileName);
    
            if (file.open(&root, logFileName, O_APPEND | O_RDWR))
            {
                if (!file.isOpen()) 
                {
                    fileSystemNeedsInit = true;
                    error ("file append error");
                    SerialUSB.println(logFileName);
                }
                else
                {
                    int cnt = 0;
                    while (curBuffer!=lastBuffer)
                    {
                        if (-1==file.write(buffer[lastBuffer], BLOCKSIZE))
                        {
                            SerialUSB.println("error writing to file");
                            fileSystemNeedsInit = true;
                            break;
                        }
                        cnt++;
                        lastBuffer++;
                        if (lastBuffer >= MAXBUFFERS)
                            lastBuffer=0;
                    }
                    unflashedBuffers = 0;
                    if (!file.close())
                    {
                        fileSystemNeedsInit = true;
                        SerialUSB.print("error appending to file ");
                    }
                    else
                    {
                        SerialUSB.print(cnt);
                        SerialUSB.println(" blocks written");
                    }                    
                }
            }
            else
            {
                SerialUSB.print("ERROR: can't append to file: ");
                SerialUSB.println(logFileName);
                fileSystemNeedsInit = true;
            }
        }
    }
}




