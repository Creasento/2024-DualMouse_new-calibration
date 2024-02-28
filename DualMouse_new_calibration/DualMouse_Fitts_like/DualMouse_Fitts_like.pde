import processing.serial.*;
import java.util.*;
import java.lang.reflect.Method;

import java.awt.*;
import java.awt.event.*;

// if true, go on the main test mode (cursor gradually disappears as it reaches to the target)
// if false, set practice mode
boolean hide = false;
int n_repeat = 5;  // repetition for a certain condition
int def_cpi = 0;
int def_pos = 0;

// CONDITION SET variables

int[] distances = {200, 400, 600, 800};  // distance settings in Fitts' Law test
int[] widths = {30, 60, 90};                     // target width fixed to 20

ArrayList<Point> dots = new ArrayList<Point>();  // history of clicked points

ArrayList<Experiment> cond = new ArrayList<Experiment>();  // list of experiment conditions
int cycle = 11;     // number of targets to be tested 

// Internal variables
int cond_no = 0;    // current condition (0, ... cond.size())
int count = 0;      // target click count within a condition
Experiment current_exp;
int count_success = 0;  // success: click in target
int count_trial = 0;    // trials: total clicks have been tried so far

Robot robot;        // mouse control robot
Serial sp;          // communication channel to the DualMouse
PrintWriter output;   // logger
int lf = 10; // \n

boolean success_prev = false;   // set true when the last click fails, it will show the previous target in red when true.
boolean clicked = false;        // internal variable for click state tracking. related to onClick, onRelease events 
String mouse_info;          // mouse report (get from 'R' command) about current CPI and POS 
int cpi = 0;                // = mouse_info
int sensor_pos = 0;         // = mouse_info

int setDelay = 0;          // when delay is needed, set this some positive value. unit: frame
String log_id = "";        // current logger's id (=timestamp)

int target_x = 0;   // internal variables to indicate the current target point w.r.t. screen center
int target_y = 0;
Point cursor_pos = new Point(0, 0); // current cursor position w.r.t screencenter


long startTime = 0;
long elapsed = 0;

void setup()
{
  Date d = new Date();
  log_id = String.format("%d", d.getTime());    // id = current timestamp
  
  // iterate over set of distances for "n_repeat" times 
  for (int i=0; i<n_repeat; i++)
  {
    for (int dist : distances)
    {
      for (int wth : widths)
      {
        cond.add(new Experiment(dist, wth));
      }
    }
  }
  
  // shuffle the conditions
  long seed = System.nanoTime();
  Collections.shuffle(cond, new Random(seed));
  // verbose
  for (int i=0; i<cond.size(); i++)
  {
    println(cond.get(i));
  }

  cond_no = 0;
  current_exp = cond.get(cond_no);

  try { 
    robot = new Robot();
    robot.setAutoDelay(0);
  } 
  catch (Exception e) {
    e.printStackTrace();
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
  frameRate(240);
  fullScreen();
  //size(1024,768);

  noCursor();
  ellipseMode(CENTER);
  rectMode(CENTER);
  
  cursor_pos= new Point(0, 0);
  println("ready");
}

void draw()
{  
  // screen fadeout when setDelay > 0
  if (setDelay > 0)
  {
    background(30);
    setDelay--;
    return;
  }
  
  background(255);
  noStroke();

  // information text printing
  fill(100);
  textAlign(LEFT, TOP);
  text("Condition " + (cond_no+1) + "/" + cond.size()+" = " +count, 10, 10);
  text(mouse_info, 10, 40);  
  if(count_trial > 0 && !hide)
  {
    float rate = (float)count_success / count_trial;
    text(count_success+" / "+count_trial+" ("+(round(rate*10000)/100)+"%)", 10, 120);
  }
  
  // set coordinate system w.r.t. screen center
  int center_x = width/2;
  int center_y = height/2;
  pushMatrix();
  translate(center_x, center_y); // set origin at the center of the screen
 
  // Fitts' Law targets drawing
  float W = current_exp.W;
  float D = current_exp.D;
  
  int prev_x = 0;  
  int prev_y = 0;

  fill(127);
  
  // formula: make the target to be opposite of the previous target, like 0-3-1-4-2-0 when cycle=7  
  int prev_target = ((count-1)%2 * cycle/2 + (count-1)/2 + (count-1)%2) % cycle;
  int target = (count%2 * cycle/2 + count/2 + count%2) % cycle;
  
  for (int i=0; i<cycle; i++)    // draw all the targets, split by 360deg / cycle
  {
    float angle = radians(i * 360.0 / cycle);
    float x0 = 0;
    float y0 = -1*D/2;
    float rot_x = x0 * cos(angle) - y0 * sin(angle);
    float rot_y = x0 * sin(angle) + y0 * cos(angle);

    if (target == i) {
      target_x = round(rot_x);
      target_y = round(rot_y);
    }
    if (prev_target == i)
    {
      prev_x = round(rot_x);
      prev_y = round(rot_y);
    }
    ellipse(rot_x, rot_y, W, W);
  }

  // draw target in green
  fill(0, 255, 0);
  ellipse(target_x, target_y, W, W);

  // draw previous target in red when failed in previous click
  if (!success_prev && (prev_x != 0 || prev_y != 0) && !hide)
  {
    fill(255, 0, 0);
    ellipse(prev_x, prev_y, W, W);
  }

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
    
    if (output != null && count > 0 && count <= cycle+1)
    {
      output.println(count+"\t"+(target_x-prev_x)+"\t"+(target_y-prev_y)+"\t"
                    +trim(response)+"\t"
                    +cursor_pos.x+"\t"+cursor_pos.y+"\t"
                    +target_x+"\t"+target_y+"\t"
                    +prev_x+"\t"+prev_y);
    }
    
    // 0b#$  => #: right button, $: left button (1 when clicked)
    if ((btn_state&0x01) > 0)
    {
      clicked();
    } else
    {
      released();
    }
  }
  // constrain the cursor to be in the screen boundary
  cursor_pos.move(constrain(cursor_pos.x, -width/2, width/2), constrain(cursor_pos.y, -height/2, height/2));

  // cursor drawing
  float target_dist = dist(prev_x, prev_y, target_x, target_y);  // distance between targets
  float cur_dist = dist(prev_x, prev_y, cursor_pos.x, cursor_pos.y); // distance between previous target -- cursor
  // fade: designed to be 0% until the 1/4 pos, totally fade away (=100%) when 3/5 pos of target dist)   
  float fade = constrain(map(cur_dist, target_dist/10, target_dist*1/9, 0.0, 0.5)*2, 0.0, 1.0); 
  float alpha = 255 - (255 * fade);

  if (count == 0 || !hide)
    alpha = 255;

  // black when main mode
  fill(0,0,0, alpha);
  // when practice, show previous click points and show the cursor in blue
  if (!hide)
  {
    fill(0);    
    for(Point p : dots)
    {
      ellipse(p.x, p.y, 3, 3);
    }
    fill(0, 0, 255, alpha);    
  }
  // cursor: crosshair
  rect(cursor_pos.x, cursor_pos.y, 20, 2);
  rect(cursor_pos.x, cursor_pos.y, 2, 20);
  
  text(cursor_pos.x+", "+cursor_pos.y, 0, 0);

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
  else if (key == ' ')
  {
    count = 0;
    dots.clear();
    stopLogging(output);
    output = null;
    setDelay = 60;
  }
  if (key == 'v')
  {
    hide = !hide;
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
  if (output == null && setDelay == 0) {
    output = startLogging(cond, cond_no);
  }
  if(count == 0)  // reset timer when a new condition is shown (=count was reset to 0)
  {
    startTime = millis();
  }
  else
  {
    long taken = millis()-startTime;
    elapsed += taken;
    println(taken);
    startTime = millis();
  }
  
  // when clicked, increase the target counter
  count++;
  count_trial++;
  success_prev = (dist(cursor_pos.x, cursor_pos.y, target_x, target_y) <= current_exp.W/2);
  if(success_prev)
    count_success++;
  dots.add(new Point(cursor_pos));

  // if a condition is completely done (=total clicks = # cycle + 1)
  if (count > cycle)
  {
    // get a new condition, finalize the logger, and reset the histories
    count = 0;
    stopLogging(output);
    output = null;
    dots.clear();
    cond_no++;
    println(cond_no+" / "+cond.size());
    
    if (cond_no >= cond.size()) // end of conditions
    {
      exit();
      println("EXIT!");
      println("Time: "+elapsed/1000.0+" sec");
      float rate = (float)count_success / count_trial;
      println(count_success+", "+count_trial+", "+(round(rate*10000)/100)+"%");
    } else
    {
      current_exp = cond.get(cond_no);
    }    
    setDelay = 60;    // blank the screen for 60 frames
  } else if (hide)  
  {
    // reset cursor pos only when hide, giving a feeling that a user clicked the target perfectly.
    cursor_pos.move(target_x, target_y);
  }
}

void onRelease()
{
  return;
}

PrintWriter startLogging(ArrayList<Experiment> conditions, int condition_no)
{
  Experiment exp = conditions.get(condition_no);
  String appen = "_";
  if(!hide)
    appen += "practice";
  else
    appen += "main";
  appen += "_"+cpi+"_"+sensor_pos;
  
  String logName = "./"+log_id+appen+"_logs/" + exp + "_" + condition_no + ".log";
  PrintWriter pw = createWriter(logName);
  count = 0;

  return pw;
}

void stopLogging(PrintWriter pw)
{
  if(pw != null)
  {
    pw.flush();
    pw.close();
  }
  pw = null;
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
