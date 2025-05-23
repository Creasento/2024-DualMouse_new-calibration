import processing.serial.*;
import java.util.*;
import java.lang.reflect.Method;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

import java.awt.*;
import java.awt.event.*;

//circle

Serial sp;

String mouse_info;
int cpi;
int sensor_pos;
int def_cpi = 0;
int def_pos = 0;
float cpi_multiplier;
int lf = 10;
int pointSize = 50;

Point cursor_pos = new Point(0, 0);
Point target = new Point(0, 0);
Point prev = new Point(0, 0);

boolean test = false;
boolean clicked = false;
boolean success_prev = false;

int setDelay = 0;
int frameRate = 75;

int nPos = 9;
int[] pos = {0, 12, 25, 37, 50, 62, 75, 87, 100};
color[] poscol = {
  color(0, 0, 255),
  color(0, 0, 127),
  color(0, 0, 0),
  color(127, 0, 0),
  color(255, 0, 0),
  color(0, 255, 0),
  color(0, 127, 0),
  color(127, 127, 0),
  color(0, 127, 127)
};

int nRepeat = 2;
int cycle = 11; //number of circle
int[] distances = {200, 400, 600};
int[] widths = {30, 60, 90};

int current_cond = 0;
Experiment current_exp;

int cnt = 0;
int cnt_trial = 0;
int cnt_success = 0;

PrintWriter Main_Logger;
PrintWriter Pos_Logger;
String log_id = "";

ArrayList<Experiment> cond = new ArrayList<Experiment>();
ArrayList<PVector> dots = new ArrayList<PVector>();
ArrayList<PVector> Positions = new ArrayList<PVector>(nPos);
ArrayList<Float> pos_values = new ArrayList<Float>();

float senPos = 0.5;
boolean visibleMode = false;
float val = 0.5;

void setup() {

  LocalDateTime now = LocalDateTime.now();
  DateTimeFormatter fmt = DateTimeFormatter.ofPattern("yyyy_MM_dd_HH_mm_ss");
  log_id = now.format(fmt);

  for (int i = 0; i < nRepeat; i++) {
    for (int D : distances) {
      for (int W : widths) {
        cond.add(new Experiment(D, W));
      }
    }
  }

  for (int i = 0; i < nPos; i++) {
    Positions.add(new PVector(0, 0));
  }

  long seed = System.nanoTime();
  Collections.shuffle(cond, new Random(seed));

  current_cond = 0;
  current_exp = cond.get(current_cond);

  printArray(Serial.list());
  String portName = Serial.list()[Serial.list().length - 1];
  portName = "/dev/cu.usbmodemHIDHE1";

  sp = new Serial(this, "COM6", 115200);
  sp.clear();


  println("READY");


  if (def_cpi != 0) setCPI(sp, def_cpi);
  if (def_pos != 0) setPOS(sp, def_pos);

  getMouseInfo(sp);
  setNpos(nPos);


  println("READY");


  Pos_Logger = StartLogging_Pos();
  Pos_Logger.println("Distance,Width,Count,PositionValue,Success");

  cpi_multiplier = (float)cpi / 12000;

  pos_values.add(sensor_pos /100.0);

  cursor_pos = new Point(0, 0);

  fullScreen();
  //frameRate(frameRate);
  noCursor();

  textSize(24);
  ellipseMode(CENTER);
  rectMode(CENTER);

  println("READY");
}


void draw() {

  if (setDelay > 0) {
    background(30);

    if (cnt_trial == 0) {
      textAlign(CENTER, CENTER);
      text("READY", width/2, height/2 - 20);
      text(setDelay/frameRate + 1, width/2, height/2 + 20);
      text("Current Mode | " + (test ? "Test" : "Practice"), width/2, height - 30);
    }

    setDelay--;
    return;
  }

  background(255);
  noStroke();

  fill(25);
  textAlign(LEFT, TOP);
  text("Current Mode | " + (test ? "Test" : "Practice"), 10, 10);
  text("Session | " + (current_cond + 1) + " / "  + cond.size(), 10, 75);
  text(mouse_info.replace(":", "|"), 10, 109);

  if (!test) {
    textAlign(RIGHT, TOP);
    float acc = ((float)cnt_success / cnt_trial) * 100;
    text("Accuracy | " + acc + "%", width - 10, 10);
    text("( " + cursor_pos.x + " , " + cursor_pos.y + " )", width - 10, 44);
  }

  textAlign(CENTER, CENTER);
  text(cnt + "/" + cycle, width/2, height/2);

  fill(150);
  rect(60, height/2, 80, 50*(nPos+1), 10);

  for (int i = 0; i < nPos; i++) {

    fill(poscol[i]);
    ellipse(60, (height/2 - 50*((nPos-1)/2)) + 50*i, 10, 10);
  }

  fill(100);

  Point center = new Point(width/2, height/2);
  pushMatrix();
  translate(center.x, center.y);

  float D = current_exp.D;
  float W = current_exp.W;

  prev = new Point(0, 0);

  int prev_target_num = ((cnt - 1)%2 * cycle/2 + (cnt-1)/2 + (cnt-1)%2) % cycle;
  int target_num = (cnt%2 * cycle/2 + cnt/2 + cnt%2) % cycle;

  for (int i = 0; i < cycle; i++) {
    float angle = radians(i * 360.0 / cycle);
    float x0 = 0;
    float y0 = -D/2;
    float rot_x = x0 * cos(angle) - y0 * sin(angle);
    float rot_y = x0 * sin(angle) + y0 * cos(angle);

    if (target_num == i) {
      target = new Point(round(rot_x), round(rot_y));
    }
    if (prev_target_num == i) {
      prev = new Point(round(rot_x), round(rot_y));
    }

    ellipse(rot_x, rot_y, pointSize, pointSize);
  }
  //circle fill green that next target
  fill(0, 255, 0);
  ellipse(target.x, target.y, pointSize, pointSize);

  //when click wrong, circle turn red
  /*
  if (!success_prev && cnt != 0 && !test) {
   fill(255, 0, 0);
   ellipse(prev.x, prev.y, pointSize, pointSize);
   }
   */

  while (sp.available() > 0) {
    String resp = sp.readStringUntil(lf);
    if (resp == null) continue;

    String[] msg = splitTokens(trim(resp), "\t");
    if (msg.length != 8) continue;

    long timestamp = Long.parseLong(msg[0]);
    int f_dx = int(msg[1]);
    int f_dy = int(msg[2]);
    int r_dx = int(msg[3]);
    int r_dy = int(msg[4]);
    int m_dx = int(msg[5]);
    int m_dy = int(msg[6]);
    int btn = int(msg[7]);

    cursor_pos.translate(m_dx, m_dy);

    if (Main_Logger != null && cnt > 0 && cnt <= cycle + 1) {
      String log = cnt + "\t" + (target.x - prev.x) + "\t" + (target.y - prev.y) + "\t" +
        trim(resp) + "\t" + cursor_pos.x + "\t" + cursor_pos.y + "\t" +
        target.x + "\t" + target.y + "\t" +
        prev.x + "\t" + prev.y;

      Main_Logger.println(log);
    }

    if ((btn & 0x01) > 0) {
      Clicked();
    } else {
      Released();
    }

    if (abs(f_dx) + abs(f_dy) + abs(r_dx) + abs(r_dy) != 0) {
      for (int i = 0; i < nPos; i++) {
        float CurrentPos = pos[i]/100.0;
        float vx = f_dx * (1.0 - CurrentPos) + r_dx * CurrentPos;
        float vy = f_dy * (1.0 - CurrentPos) + r_dy * CurrentPos;
        //old version circuit mouse
        
        //float vx =- f_dx * (1.0 - CurrentPos) + r_dx * CurrentPos;
        //float vy =- f_dy * (1.0 - CurrentPos) + r_dy * CurrentPos;

        vx *= cpi_multiplier;
        vy *= cpi_multiplier;

        Positions.get(i).x = constrain(Positions.get(i).x + vx, -width/2, width/2);
        Positions.get(i).y = constrain(Positions.get(i).y + vy, -height/2, height/2);
      }
    }
  }

  cursor_pos.move(constrain(cursor_pos.x, -width/2, width/2), constrain(cursor_pos.y, -height/2, height/2));

  // gradiant mode
  float startX = Positions.get(0).x;
  float startY = Positions.get(0).y;
  float endX = Positions.get(nPos-1).x;
  float endY = Positions.get(nPos-1).y;

  float lineLength = dist(startX, startY, endX, endY);
  float centerX = (startX + endX) / 2;
  float centerY = (startY + endY) / 2;
  float radius = lineLength / 2;

  //gradient radius of each steps
  float x1 = val*3;
  float x2 = val*4;
  float x3 = val*5;
  float x4 = val*6;

  //draw gradient
  noStroke();
  fill(250, 100);
  ellipse(centerX, centerY, lineLength*x4, lineLength*x4);
  noStroke();
  fill(225, 100);
  ellipse(centerX, centerY, lineLength*x3, lineLength*x3);
  noStroke();
  fill(200, 100);
  ellipse(centerX, centerY, lineLength*x2, lineLength*x2);
  noStroke();
  fill(175, 100);
  ellipse(centerX, centerY, lineLength*x1, lineLength*x1);
  noStroke();
  fill(150, 100);
  ellipse(centerX, centerY, lineLength, lineLength);
  noStroke();
  fill(100, 100);
  ellipse(centerX, centerY, lineLength, lineLength);

  float slope = (float)(endY - startY) / (endX - startX);
  float yIntercept = startY - slope *  startX;
  float xLeft, xRight, yLeft, yRight;
  xRight = -width;
  xLeft = width;
  yRight = slope * xRight + yIntercept;
  yLeft = slope * xLeft + yIntercept;

  if (visibleMode) {
    stroke(0);
    strokeWeight(2);
    line(xLeft, yLeft, xRight, yRight);
    noFill();
    stroke(255, 0, 0);
    strokeWeight(2);
    line(startX, startY, endX, endY);
  }

  float normalSlope = -1 / slope;
  float normalYIntercept = target.y - normalSlope * target.x;
  float intersectionX = (normalYIntercept - yIntercept) / (slope - normalSlope);
  float intersectionY = slope * intersectionX + yIntercept;

  if (visibleMode) {
    stroke(0, 255, 0);
    strokeWeight(2);
    line(target.x, target.y, intersectionX, intersectionY);
  }

  float pointCX = intersectionX;
  float pointCY = intersectionY;

  //line that distance middle of point-middle of the pointer @
  if (visibleMode) {
    stroke(0);
    strokeWeight(2);
    line(centerX, centerY, target.x, target.y);
  }

  for (int i = 0; i < nPos; i++) {
    PVector CurrentPoint = Positions.get(i);
    noStroke();
    fill(poscol[i], test ? 255 : 255);
    //point of line @
    if (visibleMode) {
      ellipse(CurrentPoint.x, CurrentPoint.y, 5, 5); //sensor circle
    }
  }

  for (PVector p : dots) {
    //after click
    fill(0, 0, 255); //blue point was left on screen(click point)
    ellipse(p.x, p.y, 5, 5);
  }

  float xFlip = endX-startX;
  float cFlip = pointCX-startX;
  int flip = 1;
  float senDist = dist(startX, startY, pointCX, pointCY);
  float senVal = senDist/lineLength;

  if (xFlip > 0 && cFlip > 0 || xFlip < 0 && cFlip < 0) {
    flip = 1;
  } else {
    flip = -1;
  }
  senPos = senVal*flip;

  fill(25);
  
  textAlign(RIGHT, TOP);
  text(senPos,  width/2-10, -height/2+78); //+34
  textAlign(LEFT, TOP);
  text("Enter: drawMode",  -width/2+10, -height/2+172); //+34
  text("+: gradientPlus",  -width/2+10, -height/2+206); //+34
  text("-: gradientMinus",  -width/2+10, -height/2+240); //+34
  
  fill(25,35);
  textAlign(LEFT, BOTTOM);
  text("CircleMode_V1.0",  -width/2+10, height/2-16); //+34
  
  popMatrix();
  
}


void Clicked() {

  if (clicked != true) OnClick();
  clicked = true;
}


void Released() {

  if (clicked != false) OnRelease();
  clicked = false;
}


void OnClick() {

  if (Main_Logger == null && setDelay == 0) {
    Main_Logger = StartLogging_Main(cond, current_cond);
  }

  PVector near = getNearest(Positions.get(0), Positions.get(nPos-1), toPV(target));

  cnt++;
  cnt_trial++;
  success_prev = dist(near.x, near.y, target.x, target.y) <= current_exp.W/2;

  if (success_prev) cnt_success++;
  dots.add(near);

  if (cnt > 1) {
    if (senPos > 0 && senPos < 1) {
      String Log = current_exp.toString().replace("_", ",") + "," + (cnt-1) + "," + String.format("%.2f", senPos) + "," + ("T");
      Pos_Logger.println(Log);
      Pos_Logger.flush();
    } else {
      String Log = current_exp.toString().replace("_", ",") + "," + (cnt-1) + "," + String.format("%.2f", senPos) + "," + ("F");
      Pos_Logger.println(Log);
      Pos_Logger.flush();
    }
  }

  if (cnt > cycle) {
    cnt = 0;
    StopLogging(Main_Logger);
    Main_Logger = null;
    dots.clear();
    current_cond++;

    if (current_cond > cond.size()-1) {
      StopLogging(Pos_Logger);
      exit();
      println("EXIT");
      float acc = (float)cnt_success / cnt_trial;
      println("Accuracy : " + acc);
    } else {
      current_exp = cond.get(current_cond);
    }

    setDelay = int(frameRate * 0.25);
  } else {
    cursor_pos.move(target.x, target.y);
    Positions.clear();

    for (int i = 0; i < nPos; i++) {
      Positions.add(new PVector(target.x, target.y));
    }
  }
}


void OnRelease() {

  return;
}


int setCPI(Serial port, int newCPI) {

  port.write("s\n");
  port.clear();

  port.write("C" + newCPI + "\n");
  port.clear();

  String read = "";

  while (splitTokens(trim(read)).length != 2) {
    read = null;
    while (read == null) read = port.readStringUntil(lf);
  }

  cpi_multiplier = (float)newCPI / 12000;

  port.write("S\n");
  return int(splitTokens(trim(read))[0]);
}


int setPOS(Serial port, int newPOS) {

  port.write("s\n");
  port.clear();

  port.write("P" + newPOS + "\n");
  port.clear();

  String read = "";

  while (splitTokens(trim(read)).length != 2) {
    read = null;
    while (read == null) read = port.readStringUntil(lf);
  }

  port.write("S\n");
  return int(splitTokens(trim(read))[0]);
}


void getMouseInfo(Serial port) {

  port.write("s\n");
  port.clear();

  port.write("R\n");
  port.clear();

  String read = "";

  while (splitTokens(trim(read)).length != 2) {
    read = null;
    while (read == null) read = port.readStringUntil(lf);
  }

  sensor_pos = int(splitTokens(trim(read))[1]);
  mouse_info = "Current Sensor Position : " + sensor_pos + "\n";

  read = null;
  while (read == null) read = port.readStringUntil(lf);

  cpi = int(splitTokens(trim(read))[1]);
  mouse_info += "Current CPI : " + cpi;

  port.clear();
  port.write("S/n");
}


void setNpos(int nPos) {

  if (nPos == 1) {
    pos = new int[]{50};
  } else {
    pos = new int[nPos];

    for (int i = 0; i < nPos; i++) {
      pos[i] = int(100*((float)i/(nPos-1)));
    }
  }

  Positions.clear();

  for (int i = 0; i < nPos; i++) {
    Positions.add(new PVector(0, 0));
  }

  cursor_pos.move(0, 0);
}


PrintWriter StartLogging_Pos() {

  String CurrentMode = test ? "Main" : "Practice";
  String msinfo = cpi + "_" + sensor_pos;
  String LogName = "./Logs/" + log_id + "_" + CurrentMode + "_" + msinfo + "_logs/Pos_values.csv";

  PrintWriter pw = createWriter(LogName);
  return pw;
}


PrintWriter StartLogging_Main(ArrayList<Experiment> conditions, int cond_num) {

  Experiment exp = conditions.get(cond_num);
  String CurrentMode = test ? "Main" : "Practice";
  String msinfo = cpi + "_" + sensor_pos;

  String logName = "./Logs/" + log_id + "_" + CurrentMode + "_" + msinfo + "_" + "logs/" + exp + "_" + (cond_num + 1) + ".log";
  PrintWriter pw = createWriter(logName);
  cnt = 0;

  return pw;
}


void StopLogging(PrintWriter pw) {

  if (pw != null) {
    pw.flush();
    pw.close();
  }

  pw = null;
}


PVector toPV(Point p) {

  float px = (float)p.x;
  float py = (float)p.y;

  return new PVector(px, py);
}


float getDist(PVector s, PVector e, PVector p) {

  PVector sp = PVector.sub(p, s);
  PVector se = PVector.sub(e, s);

  PVector cross = sp.cross(se);
  float dist = cross.mag() / se.mag();

  return dist;
}


PVector getNearest(PVector s, PVector e, PVector p) {

  PVector se = PVector.sub(e, s);
  PVector sp = PVector.sub(p, s);

  float mag = constrain(sp.dot(se) / se.magSq(), 0.0, 1.0);
  if (cnt != 0)pos_values.add(mag);
  PVector proj = se.mult(mag);

  return new PVector(s.x + proj.x, s.y + proj.y);
}


void keyPressed() {

  if (keyCode == UP) {
    setCPI(sp, cpi + 100);
    getMouseInfo(sp);
  } else if (keyCode == DOWN) {
    setCPI(sp, cpi - 100);
    getMouseInfo(sp);
  } else if (keyCode == RIGHT) {
    setPOS(sp, sensor_pos + 5);
    getMouseInfo(sp);
  } else if (keyCode == LEFT) {
    setPOS(sp, sensor_pos - 5);
    getMouseInfo(sp);
  } else if (key == 'M' || key == 'm') {
    test = !test;
  } else if (key == '>' || key == '.') {
    nPos += 2;
    nPos %= 10;
    setNpos(nPos);
  } else if (key == '<' || key == ',') {
    nPos += 8;
    nPos %= 10;
    setNpos(nPos);
  } else if (key == ESC) {
    key = 0;
    StopLogging(Main_Logger);
    StopLogging(Pos_Logger);
    exit();
  } else if (key == ENTER) {
    visibleMode = !visibleMode;
  } else if (key == '+') {
    val += 0.1;
  } else if (key == '-') {
    val -= 0.1;
  }
}
