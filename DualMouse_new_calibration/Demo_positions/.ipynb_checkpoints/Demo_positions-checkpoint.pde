import processing.serial.*;
import java.util.*;
import java.lang.reflect.Method;

import java.awt.*;
import java.awt.event.*;

class PVector {

  float x;
  float y;

  PVector(float x_, float y_) {
    x = x_;
    y = y_;
  }
}

// if true, go on the main test mode (cursor gradually disappears as it reaches to the target)
// if false, set practice mode
int def_cpi = 0;   // set 0 if use the device cpi as-is
int def_pos = 0;   // set 0 if use the device pos as-is

int nPos = 5;
int[] pos = {0, 25, 50, 75, 100};
color[] posColors = 
  {
    color(0, 0, 255),
    color(0, 0, 127),
    color(0, 0, 0),
    color(127, 0, 0),
    color(255, 0, 0)
  };
ArrayList<ArrayList<PVector>> traces = new ArrayList<ArrayList<PVector>>(nPos);

// CONDITION SET variables

// Internal variables
Robot robot;        // mouse control robot
Serial sp;          // communication channel to the DualMouse
PrintWriter output;   // logger
int lf = 10; // \n

boolean success_prev = false;   // set true when the last click fails, it will show the previous target in red when true.
boolean clicked = false;        // internal variable for click state tracking. related to onClick, onRelease events 
String mouse_info;          // mouse report (get from 'R' command) about current CPI and POS 
int cpi = 0;                // = mouse_info
int sensor_pos = 0;         // = mouse_info

Point cursor_pos = new Point(0, 0); // current cursor position w.r.t screencenter

boolean doTrace = false;
Point traceStartPoint = new Point(0,0);

long startTime = 0;
long elapsed = 0;

float cpi_multiplier = 0.1;

void setup()
{
  try { 
    robot = new Robot();
    robot.setAutoDelay(0);
  } 
  catch (Exception e) {
    e.printStackTrace();
  }
  
  for(int i=0;i<nPos;i++)
  {
    traces.add(new ArrayList<PVector>());
  }

  // List all the available serial ports:
  printArray(Serial.list());
  // connect to the last port in the list;
  String portName = Serial.list()[Serial.list().length - 1];

  // connect to the mouse
  sp = new Serial(this, portName, 115200);
  sp.clear();

  // set the default mouse params
  if(def_cpi != 0)
    setCPI(sp, def_cpi);
  if(def_pos != 0)
    setPos(sp, def_pos);
  
  // report the current setting from mouse (to verify the setting is correctly set)
  getMouseInfo(sp);
  //sp.buffer(20);

  //size(1000, 500);
  textSize(24);
  frameRate(10);
  fullScreen();
  //size(1024,768);

  noCursor();
  ellipseMode(CENTER);
  rectMode(CENTER);
  
  cursor_pos= new Point(0, 0);
  println("ready");
  
  cpi_multiplier = (float)cpi / 12000;
}

void draw()
{  
  
  background(255);
  noStroke();

  // information text printing
  fill(100);
  textAlign(LEFT, TOP);
  text(mouse_info, 10, 10);  
    
  // set coordinate system w.r.t. screen center
  int center_x = width/2;
  int center_y = height/2;
  pushMatrix();
  translate(center_x, center_y); // set origin at the center of the screen
 
  int prev_x = 0;  
  int prev_y = 0;
  
  // draw mouse figure
  fill(200);
  stroke(0);
  
  int mW = 50;
  int mH = 100;
  rect(-200 - mW/2, 0 - mH/2, mW, mH, 5);
  
  noStroke();
  float step = (float)mH / (nPos+1);
    
  for(int i=0;i<nPos;i++)
  {
    fill(posColors[i]);
    ellipse(-200 - mW/2, 0-mH + step+(step*i), 5, 5);
  }
  
  strokeWeight(2);
  
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
    
    // when logger is opened, trial has been started, and not ended
    cursor_pos.translate(m_dx, m_dy); // update the cursor with the mouse log event
    
        
    // 0b#$  => #: right button, $: left button (1 when clicked)
    if ((btn_state&0x01) > 0)
    {
      clicked();
    } else
    {
      released();
    }
    
    // record traces
    if (doTrace && abs(f_dx)+abs(f_dy)+abs(r_dx)+abs(r_dy) != 0)
    {
      for(int i=0;i<nPos;i++)
      {
        float currentPos = pos[i] / 100.0;
        float pos_dx = (f_dx*(1.0 - currentPos) + r_dx*currentPos) * cpi_multiplier;
        float pos_dy = (f_dy*(1.0 - currentPos) + r_dy*currentPos) * cpi_multiplier;
        
        traces.get(i).add(new PVector(pos_dx, pos_dy));
      }
    }
  }
  
  // draw traces
  for(int i=0;i<nPos;i++)
  {
    ArrayList<PVector> current_trace = traces.get(i);
    
    float px = traceStartPoint.x;
    float py = traceStartPoint.y;
    
    noFill();
    stroke(posColors[i]);
    
    beginShape();
    vertex(px,py);      
    for(int j=0;j<current_trace.size();j++)
    {
      PVector p = current_trace.get(j);       
      px += p.x;
      py += p.y;
      vertex(px, py);
    }
    endShape();
  }
  
  // constrain the cursor to be in the screen boundary
  cursor_pos.move(constrain(cursor_pos.x, -width/2, width/2), constrain(cursor_pos.y, -height/2, height/2));

  // cursor: crosshair
  if(!doTrace)
  {
    fill(0);
    noStroke();
    rect(cursor_pos.x, cursor_pos.y, 20, 2);
    rect(cursor_pos.x, cursor_pos.y, 2, 20);
  }
  
  popMatrix();
  
  // retain the real mouse cursor fixed at the center.
  mouseMove(center_x, center_y);
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
  traceOn();
  println("Trace on");
}

void onRelease()
{
  traceOff();
  println("Trace off");
}

void traceOn()
{
  doTrace = true;
  
  for(int i=0;i<nPos;i++)
  {
    traces.get(i).clear();
  }
  traceStartPoint = new Point(cursor_pos.x, cursor_pos.y);
}

void traceOff()
{
  doTrace = false;
}


// get current mouse cursor location
Point getGlobalMouseLocation() {
  // java.awt.MouseInfo
  PointerInfo pointerInfo = MouseInfo.getPointerInfo();
  Point p = pointerInfo.getLocation();
  return p;
}

// move mouse cursor to specific position
void mouseMove(Point p)
{
  mouseMove(p.x, p.y);
}

void mouseMove(int x, int y) {
  robot.mouseMove(x, y);
}
