import processing.serial.*;
import java.util.*;
import java.lang.reflect.Method;

import java.awt.*;
import java.awt.event.*;

Serial sp;
String mouse_info;          // mouse report (get from 'R' command) about current CPI and POS 
int cpi = 0;                // = mouse_info
int sensor_pos = 0;         // = mouse_info
int lf = 10;
boolean clicked = false;

void setup()
{
  // List all the available serial ports:
  printArray(Serial.list());
  // connect to the last port in the list;
  String portName = Serial.list()[Serial.list().length - 1];

  // connect to the mouse
  sp = new Serial(this, portName, 115200);
  sp.clear();

  // report the current setting from mouse (to verify the setting is correctly set)
  getMouseInfo(sp);
  //sp.buffer(20);

  //size(1000, 500);
  textSize(24);
  frameRate(240);
  size(400,150);

  ellipseMode(CENTER);
  rectMode(CENTER);
  println("ready");
}

void draw()
{  
  background(255);
  noStroke();

  // information text printing
  fill(100);
  textAlign(LEFT, TOP);
  text(mouse_info, 10, 10);  
  
  // Mouse position update
  while (sp.available() > 0)
  {
    String response = sp.readStringUntil(lf);
    if (response == null)
      continue;
      
    // parse mouse messages    
    String[] message = splitTokens(trim(response), "\t");
    if (message.length != 8)
      continue;
    long timestamp = Long.parseLong(message[0]);
    int f_dx = int(message[1]);  // front sensor dx, dy
    int f_dy = int(message[2]);
    int r_dx = int(message[3]);  // rear sensor dx/dy
    int r_dy = int(message[4]);
    int m_dx = int(message[5]);  // generate mouse movement dx/dy
    int m_dy = int(message[6]);
    int btn_state = int(message[7]);
    
    
    //if (output != null && count > 0 && count <= cycle+1)
    //{
    //  output.println(count+"\t"+(target_x-prev_x)+"\t"+(target_y-prev_y)+"\t"
    //                +trim(response)+"\t"
    //                +cursor_pos.x+"\t"+cursor_pos.y);
    //}
    
    // 0b#$  => #: right button, $: left button (1 when clicked)
    if ((btn_state&0x01) > 0)
    {
      clicked();
    } else
    {
      released();
    }
  }
}

void getMouseInfo(Serial port)
{
  port.write("s\n"); // command stop report
  port.clear();
  port.clear();
  port.clear();

  port.write("R\n");  
  String readed = "";

  while (splitTokens(trim(readed)).length != 2)
  {
    readed = null; 
    while (readed == null) readed = sp.readStringUntil(lf);
  }

  sensor_pos = int(splitTokens(trim(readed))[1]);
  mouse_info = "Current sensor position = "+sensor_pos+"%\n";
  readed = null; 
  while (readed == null) readed = sp.readStringUntil(lf);
  cpi = int(splitTokens(trim(readed))[1]);
  mouse_info += "Current CPI = " + cpi;

  port.clear();
  port.write("S\n"); // command restart report
}

int setCPI(Serial port, int newCPI)
{
  port.write("s\n"); // command stop report
  port.clear();
  
  port.write("C"+newCPI+"\n");  // command to set new CPI
  String readed = ""; 
  
  while (splitTokens(trim(readed)).length != 2)
  {
    readed = null; 
    while (readed == null) readed = sp.readStringUntil(lf);
  }
  
  port.write("S\n"); // command to restart reporting

  return int(splitTokens(trim(readed))[0]);
}

int setPos(Serial port, int newPos)
{
  port.write("s\n"); // command stop report
  port.clear();

  port.write("P"+newPos+"\n");  // command to set new CPI
  String readed = ""; 
  while (splitTokens(trim(readed)).length != 1)
  {
    readed = null; 
    while (readed == null) readed = sp.readStringUntil(lf);
  }

  port.write("S\n"); // command to restart reporting
  return int(splitTokens(trim(readed))[0]);
}

void keyPressed()
{
  if (keyCode == UP)
  {
    setCPI(sp, cpi + 100);
    getMouseInfo(sp);
  }
  else if (keyCode == DOWN)
  {
    setCPI(sp, cpi - 100);
    getMouseInfo(sp);
  }
  else if (keyCode == RIGHT)
  {
    setPos(sp, sensor_pos + 5);
    getMouseInfo(sp);
  }
  else if (keyCode == LEFT)
  {
    setPos(sp, sensor_pos - 5);
    getMouseInfo(sp);
  }
}

void clicked()
{
  if (clicked != true) onClick();
  clicked = true;
}

void released()
{
  if (clicked != false) onRelease();
  clicked = false;
}

void onClick()
{   
  return;
}

void onRelease()
{
  return;
}
