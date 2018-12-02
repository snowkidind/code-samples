/*

Project: Point Source, Laser Pointer Detection Tool
Author: Keny Ruyter, 2016

This project was used for an invention I made related to detecting a laser pointer during 
public presentations.

This segment is from a program I wrote, which interacts with openCV in order to detect the 
position of a television screen and create an accurate image from which to do further processing 
on detecting the laser pointer's position.

in this function, an array of raw data is provided from a camera that is assumed to be 
pointing at a tv screen. First the edges of the screen are detected, and then from that, 
corners are detected, then the original image is warped and cropped to the detected dimensions 
of the television display. 

If you have seen a projector auto detect a screen I would suppose this is similar, but probably 
an improvement to that, because of the use of data from a charge couple device.

*/

cv::Mat PointSource::analyzeLines(cv::Mat bw)
{

    // 
    if (!inited){
        stallTimer += 1;
        if (stallTimer >= stallTimerDuration){
            inited = true;
            stallTimer = 0;
        }
        // stall for a minute before accepting data
        return bw;
    }
    
    // reallocate the bw array with proper file format
    cv::cvtColor(bw, bw, CV_BGRA2BGR);
    
    // save an unmutated copy
    cv::Mat reference = bw.clone();

    // assume any undisclosed variable like this is an instance/class variable set in the header file
    if (init){
        north.setRows(bw.rows);
        south.setRows(bw.rows);
        east.setRows(bw.cols);
        west.setRows(bw.cols);
        init = false;
    }
    
    // Solution will be our array solution, which will eventually contain 4 lines that 
    // define the rectangle in the image we are detecting. This code is run perpetually 
    // so only calculate heavy things as needed 
    if (solution.size() < 4){
               
        ////// noise removal tactics //////
        
        // the blue channel does not help us find a red dot so remove.
        Mat channel[3];
        split(bw, channel);
        channel[0] = Mat::zeros(bw.rows, bw.cols, CV_8UC1);
        channel[1] = Mat::zeros(bw.rows, bw.cols, CV_8UC1);
        cv::merge(channel,3, bw);

        // antialias the image
        for ( int i = 1; i < 10; i = i + 2 )
            blur( bw, bw, Size( i, i ), Point(-1,-1));
        
        // grayscale
        cv::cvtColor(bw, bw, CV_BGR2GRAY);

        // threshold the image (uses GUI sliders)
        threshold( bw, bw, slider1, slider2, CV_THRESH_BINARY_INV);
    }

    // canny, edge detection
    // input array - filter Source image, grayscale
    // Output array - Output of the detector (can be the same as the input)
    // thresh 1 lowThreshold: The value entered by the user moving the Trackbar
    // thresh 2 highThreshold: Set three times the lower threshold (following Canny’s recommendation)
    // apeture size / kernel_size: default 3 (the size of the Sobel kernel to be used internally)
    // l2 gradient (false)
    if (solution.size() < 4){
        cv::Canny(bw, bw, slider3, slider3 * 3, 3);
    }

    // define the output vector array of lines
    std::vector<cv::Vec4i> lines;
    std::vector<cv::Vec4i> linesA;
    cv::Size s = bw.size();
    
    // Hough Lines: Finds line segments in a binary image using the probabilistic Hough transform.
    // detect straight lines in the image, returns lines
    // output vector stores the parameters (x_{start}, y_{start}, x_{end}, y_{end}) of the detected lines
    // rho (Distance resolution of the accumulator in pixels.)
    // theta in degrees, 1 Degree (CV_PI/180) Angle resolution of the accumulator in radians
    // thresh minimum number of intersections to detect a line Accumulator threshold
    // min line length
    // maxLineGap The maximum gap between two points to be considered in the same line.
    if (solution.size() < 4){
        cv::HoughLinesP(bw, linesA, 1, CV_PI/180, slider4, slider5, slider6);
        cv::cvtColor(bw, bw, CV_GRAY2BGR);
    }

    // once lines are found expand them to reach from one side of the view to the other
    for (int i = 0; i < linesA.size(); i++){
        
        // before expanding the lines, we should determine if the line has advanced too far
        // ideally a line should have key on the inside and not key on the outside.
        
        // reference color points at center of ref, what the camera sees at center
        Vec3b intensity = reference.at<Vec3b>(Point(bw.cols/2, bw.rows/2));
        float blueRef = intensity.val[0];
        float greenRef = intensity.val[1];
        float redRef = intensity.val[2];
        
        // This approach uses min max values to determine the dimensions of the downstage monitor
        // difference between x coordinates of the line - abs returns positive value.
        int difference = abs(linesA[i][2] - linesA[i][0]);
        
        // difference between y coordinates of the line
        int difference2 = abs(linesA[i][1] - linesA[i][3]);
        
        int checkRange = 40;
        
        // one way to look at it would be to analyze the gender identity (h or V)
        // of the line and then auto adjust min max thresh to the bulk of the average of lines coming in...
        // greater of the 2 will determine direction of the line...
        // difference > difference2 ? isHorizontal : isVertical
        if (difference < difference2){

            // Line may be vertical...
            // reference color points adjacent to ref
            // check against x points
            
            Point pointNeg = Point(linesA[i][0] - checkRange, linesA[i][1]); // <-- crash.
            Point pointPos = Point(linesA[i][0] + checkRange, linesA[i][1]);

            if (isValidPoint(pointNeg, bw) && isValidPoint(pointPos, bw)){
            
                Vec3b intensityNeg = reference.at<Vec3b>(pointNeg);
                float innerBlue = intensityNeg.val[0];
                float innerGreen = intensityNeg.val[1];
                float innerRed = intensityNeg.val[2];
                
                Vec3b intensityPos = reference.at<Vec3b>(pointPos);
                float outerBlue = intensityPos.val[0];
                float outerGreen = intensityPos.val[1];
                float outerRed = intensityPos.val[2];
                
                bool pass = false;
                
                // is line west side or east side?
                if (linesA[i][0] < s.width/2){
                    
                    // west quadrant
                    // disregard line if variance is > range
                    // if innerBlue is within 40 of blueRef OR outerBlue is within 40 of blueRef AND only one of them  are within the spec...
                    bool blue = compareSegmentToSource(blueRef, innerBlue, outerBlue, "west");
                    
                    // if blue is false, should compare the other two regions for high contrast
                    // if innerGreen < (by a landslide - 100++) outerGreen and innerRed < (by a landslide - 100++)  outerRed
                    bool go = false;
                    if (!blue){
                        // if blue is false, should compare the other two regions for high contrast
                        // if innerGreen < (by a landslide - 100++) outerGreen and innerRed < (by a landslide - 100++)  outerRed
                        int diffG = abs(outerGreen - innerGreen);
                        int diffR = abs(outerRed - innerRed);
                        if (diffG > secondaryThresh && diffR > secondaryThresh){
                            go = true;
                        }
                    }
                    else go = true;
                    
                    if (go){
                        // vertical lines (subject to greater perspective distortion, wider angles)
                        cv::Vec4i vec = north.expandLine(linesA[i], bw.rows, true);
                        lines.push_back(vec);
                        
                        // draw circles to verify (visual effect for technician)
                        cv::circle(bw, pointNeg, 10, GREEN);
                        cv::circle(bw, pointPos, 10, BLUE);
                    }
                    else {
                        std::string strN ( std::to_string(pointNeg.x)  + "," + std::to_string(pointNeg.y));
                        std::string strP ( std::to_string(pointPos.x)  + "," + std::to_string(pointPos.y));
                        cv::circle(bw, pointPos, 10, ORANGE);
                        cv::circle(bw, pointNeg, 10, ORANGE);
                    }
                    
                }
                else {
                    // east quadrant
                    // if innerBlue is within 40 of blueRef OR outerBlue is within 40 of blueRef AND only one of them  are within the spec...
                    bool blue = compareSegmentToSource(blueRef, innerBlue, outerBlue, "east");
                    
                    // if blue is false, should compare the other two regions for high contrast
                    // if innerGreen < (by a landslide - 100++) outerGreen and innerRed < (by a landslide - 100++)  outerRed
                    bool go = false;
                    if (!blue){
                        // if blue is false, should compare the other two regions for high contrast
                        // if innerGreen < (by a landslide - 100++) outerGreen and innerRed < (by a landslide - 100++)  outerRed
                        int diffG = abs(outerGreen - innerGreen);
                        int diffR = abs(outerRed - innerRed);
                        if (diffG > secondaryThresh && diffR > secondaryThresh){
                            go = true;
                        }
                    }
                    else go = true;
                    
                    if (go){
                        // vertical lines (subject to greater perspective distortion, wider angles)
                        cv::Vec4i vec = north.expandLine(linesA[i], bw.rows, true);
                        lines.push_back(vec);
                        
                        // draw circles to verify
                        cv::circle(bw, pointNeg, 10, GREEN);
                        cv::circle(bw, pointPos, 10, BLUE);
                    }
                    else {
                        std::string strN ( std::to_string(pointNeg.x)  + "," + std::to_string(pointNeg.y));
                        std::string strP ( std::to_string(pointPos.x)  + "," + std::to_string(pointPos.y));
                        cv::circle(bw, pointPos, 10, ORANGE);
                        cv::circle(bw, pointNeg, 10, ORANGE);
                    }
                }
            }
            else {
               // cout << "Invalid Point: " << pointNeg.x << "," << pointNeg.y <<endl;
               // cout << "Invalid Point: " << pointPos.x << "," << pointPos.y <<endl;
            }
        }
        else {
            
            // Line may be Horizontal...
            // reference color points adjacent to ref
            // check against y points
            
            // y points here
            Point pointNeg = Point(linesA[i][2], linesA[i][3] - checkRange); // <-- crash.
            Point pointPos = Point(linesA[i][2], linesA[i][3] + checkRange);
            
            if (isValidPoint(pointNeg, bw) && isValidPoint(pointPos, bw)){
                Vec3b intensityNeg = reference.at<Vec3b>(pointNeg);
                float innerBlue = intensityNeg.val[0];
                float innerGreen = intensityNeg.val[1];
                float innerRed = intensityNeg.val[2];
                
                Vec3b intensityPos = reference.at<Vec3b>(pointPos);
                float outerBlue = intensityPos.val[0];
                float outerGreen = intensityPos.val[1];
                float outerRed = intensityPos.val[2];
                
                bool pass = false;
                
                if (linesA[i][1] < s.height/2){
                    
                    // North quadrant
                    // disregard line if variance is > range
                    // if innerBlue is within 40 of blueRef OR outerBlue is within 40 of blueRef AND only one of them  are within the spec...
                    bool blue = compareSegmentToSource(blueRef, innerBlue, outerBlue, "north");
                    
                    // if blue is false, should compare the other two regions for high contrast
                    // if innerGreen < (by a landslide - 100++) outerGreen and innerRed < (by a landslide - 100++)  outerRed
                    bool go = false;
                    
                    if (!blue){
                        // if blue is false, should compare the other two regions for high contrast
                        // if innerGreen < (by a landslide - 100++) outerGreen and innerRed < (by a landslide - 100++)  outerRed
                        int diffG = abs(outerGreen - innerGreen);
                        int diffR = abs(outerRed - innerRed);
                        if (diffG > secondaryThresh && diffR > secondaryThresh){
                            go = true;
                        }
                    }
                    else go = true;
                    
                    if (go){
                        // vertical lines (subject to greater perspective distortion, wider angles)
                        cv::Vec4i vec = north.expandLine(linesA[i], bw.cols, false);
                        lines.push_back(vec);
                        
                        // draw circles to verify
                        cv::circle(bw, pointNeg, 10, RED);
                        cv::circle(bw, pointPos, 10, YELLOW);
                    }
                    else {

                        std::string strN ( std::to_string(pointNeg.x)  + "," + std::to_string(pointNeg.y));
                        std::string strP ( std::to_string(pointPos.x)  + "," + std::to_string(pointPos.y));
                        cv::circle(bw, pointPos, 10, ORANGE);
                        cv::circle(bw, pointNeg, 10, ORANGE);
                    }
                    
                }
                else {
                    // South quadrant
                    // if innerBlue is within 40 of blueRef OR outerBlue is within 40 of blueRef AND only one of them  are within the spec...
                    bool blue = compareSegmentToSource(blueRef, innerBlue, outerBlue, "south");
                    
                    // if blue is false, should compare the other two regions for high contrast
                    // if innerGreen < (by a landslide - 100++) outerGreen and innerRed < (by a landslide - 100++)  outerRed
                    bool go = false;
                    if (!blue){
                        // if blue is false, should compare the other two regions for high contrast
                        // if innerGreen < (by a landslide - 100++) outerGreen and innerRed < (by a landslide - 100++)  outerRed
                        int diffG = abs(outerGreen - innerGreen);
                        int diffR = abs(outerRed - innerRed);
                        if (diffG > secondaryThresh && diffR > secondaryThresh){
                            go = true;
                        }
                    }
                    else go = true;
                    
                    if (go){
                        // vertical lines (subject to greater perspective distortion, wider angles)
                        cv::Vec4i vec = north.expandLine(linesA[i], bw.cols, false);
                        lines.push_back(vec);
                        
                        // draw circles to verify
                        cv::circle(bw, pointNeg, 10, VIOLET);
                        cv::circle(bw, pointPos, 10, LIGHT_GREEN);
                    }
                    else {
                        std::string strN ( std::to_string(pointNeg.x)  + "," + std::to_string(pointNeg.y));
                        std::string strP ( std::to_string(pointPos.x)  + "," + std::to_string(pointPos.y));
                        cv::circle(bw, pointPos, 10, ORANGE);
                        cv::circle(bw, pointNeg, 10, ORANGE);
                    }
                }
            }
            else {
                // cout << "Invalid Point: " << pointNeg.x << "," << pointNeg.y <<endl;
                // cout << "Invalid Point: " << pointPos.x << "," << pointPos.y <<endl;
            }
        }
    }

    // Discussion:
    // This determines where the lines are on the screen.
    // First we determined which quadrant the line is in, now we average an array associated
    // with that quadrant to determine the most likely position of the screen's edge...
    // we only run this code if the solution is not completed.
    
    if (solution.size() < 4){
        
        for (int i = 0; i < lines.size(); i++)
        {
            
            // determine the difference between x coordinates of the line - abs returns positive value.
            int difference = abs(lines[i][2] - lines[i][0]);
            
            // determine the difference between y coordinates of the line
            int difference2 = abs(lines[i][1] - lines[i][3]);
            
            // Determine the attitude of the line, horizontal or vertical?
            // here we look at the x coordinates for similarity and then verify that the y coordinates are not similar.
            // since the lines can be several degrees off (loose xdiff ~30, ydiff ~100)
            // the presence of these two factors is required
            // that is, if the xFactor is small and the yFactor is large...
            if (difference < difference2){
            
                // in this case the line gender-identifies as vertical
                // if one of the x points is less than half the width of the screen, west quadrant, greater, east
                if (lines[i][0] < s.width/2){
                    
                    /////////// West Quadrant ///////////
                    
                    // now push into the west averaging array
                    if (westAverage.size() < averagingSize){
                        westAverage.push_back(lines[i]);
                    }
                    
                    // only calculate when enough data to calculate.
                    else if (westAverage.size() == averagingSize && !solvedW){
                        
                        for (int j = 0; j < westAverage.size(); j++){
                            
                            int result = west.AddLineToAverage(westAverage[j], "x");
                            if (result == 0){
                                // This is a sign of interference
                                // cout << "More Lines were detected in west quadrant" << endl;
                            }
                            // result is 2 if lines are parallel
                            else if (result == 2){
                                
                                // get the average y vector that already exists
                                cv::Vec<int, 4> vec = west.averageVector();
                                
                                // if the new line is lower in pixels than the existing average, aka, closer to the center
                                if (westAverage[j][0] > vec[0]){ // logic different based on quadrant
                                    
                                    // if this is the case, all the outer lines should be discarded and replaced with the inner line's coordinates.
                                    west.reAverage(westAverage[j], "x");
                                }
                                else {
                                    // if all outer parallel lines are detected, then the original line is probably right.
                                    // that is unless some non-parallel noise line has caused a bad seed.
                                }
                            }
                        }
                        
                        cout << "Solution for West: " << west.averageVector() << endl;
                        
                        // TODO determine if this result is acceptable and marked as solved.
                        solvedW = true;
                        
                        // The average vector stored in the line array, aka, the solution
                        cv::Vec<int, 4> vec = west.averageVector();
                        
                        // expand line to edges for corner processing...
                        vec = west.expandLine(vec, bw.rows, true);
                        
                        // Add the solution to the array
                        solution.push_back(vec);
                        
                    }
                    
                    if(!solvedW){
                        // expands detected lines
                        cv::Vec4i v = lines[i];
                        v = west.expandLine(v, bw.rows, true);
                        cv::line(bw, cv::Point(v[0], v[1]), cv::Point(v[2], v[3]), RED, 1, 8);
                    }
                    
                }
                else {
                    
                    /////////// East Quadrant ///////////
                    
                    // now push into the east averaging array
                    if (eastAverage.size() < averagingSize){
                        eastAverage.push_back(lines[i]);
                    }
                    
                    // only calculate when enough data to calculate.
                    else if (eastAverage.size() == averagingSize && !solvedE){
                        
                        for (int j = 0; j < eastAverage.size(); j++){
                            
                            int result = east.AddLineToAverage(eastAverage[j], "x");
                            if (result == 0){
                                // This is a sign of interference
                                // cout << "More Lines were detected in east quadrant" << endl;
                            }
                            // result is 2 if lines are parallel
                            else if (result == 2){
                                
                                // get the average y vector that already exists
                                cv::Vec<int, 4> vec = east.averageVector();
                                
                                // if the new line is lower in pixels than the existing average, aka, closer to the center
                                if (eastAverage[j][0] < vec[0]){ // logic different based on quadrant
                                    
                                    // if this is the case, all the outer lines should be discarded and replaced with the inner line's coordinates.
                                    east.reAverage(eastAverage[j], "x");
                                }
                                else {
                                    // if all outer parallel lines are detected, then the original line is probably right.
                                    // that is unless some non-parallel noise line has caused a bad seed.
                                }
                            }
                        }
                        
                        cout << "Solution for East: " << east.averageVector() << endl;
                        
                        // TODO determine if this result is acceptable and marked as solved.
                        solvedE = true;
                        
                        // The average vector stored in the line array, aka, the solution
                        cv::Vec<int, 4> vec = east.averageVector();
                        
                        // expand line to edges for corner processing...
                        vec = east.expandLine(vec, bw.rows, true);
                        
                        // Add the solution to the array
                        solution.push_back(vec);
                    }
                    
                    if(!solvedE){
                        
                        // expands detected lines
                        cv::Vec4i v = lines[i];
                        v = east.expandLine(v, bw.rows, true);
                        cv::line(bw, cv::Point(v[0], v[1]), cv::Point(v[2], v[3]), YELLOW, 1, 8);
                    }
                }
            }
            
            // if the y coordinates are small and x coordinates are large
            else {
                // probably horizontal
                
                // if one of the y points is less than half the height of the screen, north quadrant
                if (lines[i][1] < s.height/2){
                    
                    /////////// North Quadrant ///////////
                    
                    // now push into the north averaging array
                    if (northAverage.size() < averagingSize){
                        northAverage.push_back(lines[i]);
                    }
                    
                    // only calculate when enough data to calculate.
                    else if (northAverage.size() == averagingSize && !solvedN){
                        
                        for (int j = 0; j < northAverage.size(); j++){
                            
                            int result = north.AddLineToAverage(northAverage[j], "y");
                            if (result == 0){
                                // This is a sign of interference
                                // cout << "More Lines were detected in north quadrant" << endl;
                            }
                            // result is 2 if lines are parallel
                            else if (result == 2){
                                
                                // get the average y vector that already exists
                                cv::Vec<int, 4> vec = north.averageVector();
                                
                                // if the new line is higher in pixels than the existing average, aka, closer to the center
                                if (northAverage[j][1] > vec[1]){ // logic different based on quadrant
                                    
                                    // if this is the case, all the outer lines should be discarded and replaced with the inner line's coordinates.
                                    north.reAverage(northAverage[j], "y");
                                }
                                else {
                                    // if all outer parallel lines are detected, then the original line is probably right.
                                    // that is unless some non-parallel noise line has caused a bad seed.
                                }
                            }
                        }
                        
                        cout << "Solution for North: " << north.averageVector() << endl;
                        
                        // TODO determine if this result is acceptable and marked as solved.
                        solvedN = true;
                        
                        // The average vector stored in the line array, aka, the solution
                        cv::Vec<int, 4> vec = north.averageVector();
                        
                        // expand line to edges for corner processing...
                        vec = north.expandLine(vec, bw.cols, false);
                        
                        // Add the solution to the array
                        solution.push_back(vec);
                    }
                    
                    if(!solvedN){
                        
                        // expands detected lines
                        cv::Vec4i v = lines[i];
                        v = north.expandLine(v, bw.cols, false);
                        cv::line(bw, cv::Point(v[0], v[1]), cv::Point(v[2], v[3]), BLUE, 1, 8);
                    }
                    
                }
                else {
                    
                    /////////// South Quadrant ///////////
                    
                    // now push into the north averaging array
                    if (southAverage.size() < averagingSize){
                        southAverage.push_back(lines[i]);
                    }
                    
                    // only calculate when enough data to calculate.
                    else if (southAverage.size() == averagingSize && !solvedS){
                        
                        for (int j = 0; j < southAverage.size(); j++){
                            
                            int result = south.AddLineToAverage(southAverage[j], "y");
                            if (result == 0){
                                // This is a sign of interference
                                // cout << "More Lines were detected in South quadrant" << endl;
                            }
                            // result is 2 if lines are parallel
                            else if (result == 2){
                                
                                // get the average y vector that already exists
                                cv::Vec<int, 4> vec = south.averageVector();
                                
                                // if the new line is lower in pixels than the existing average, aka, closer to the center
                                if (southAverage[j][1] < vec[1]){ // logic different based on quadrant
                                    
                                    // if this is the case, all the outer lines should be discarded and replaced with the inner line's coordinates.
                                    // cout << "An inner parallel line was detected...  " << result << endl;
                                    south.reAverage(southAverage[j], "y");
                                }
                                else {
                                    // if all outer parallel lines are detected, then the original line is probably right.
                                    // that is unless some non-parallel noise line has caused a bad seed.
                                    // cout << "An outer parallel line was detected...  " << result << endl;
                                }
                            }
                        }
                        
                        cout << "Solution for South: " << south.averageVector() << endl;
                        
                        // TODO determine if this result is acceptable and marked as solved.
                        solvedS = true;
                        
                        // The average vector stored in the line array, aka, the solution
                        cv::Vec<int, 4> vec = south.averageVector();
                        
                        // expand line to edges for corner processing...
                        vec = south.expandLine(vec, bw.cols, false);
                        
                        // Add the solution to the array
                        solution.push_back(vec);
                    }
                    
                    if(!solvedS){
                        
                        cv::Vec4i v = lines[i];
                        v = north.expandLine(v, bw.cols, false);
                        cv::line(bw, cv::Point(v[0], v[1]), cv::Point(v[2], v[3]), YELLOW, 1, 8);
                    }
                }
            }
//            else {
//                // Could not determine attitude of line based on data
//                cv::line(bw, cv::Point(lines[i][0], lines[i][1]), cv::Point(lines[i][2], lines[i][3]), LIGHT_GREEN, 1, 8);
//            }
        }
    }
    
    // display solution lines when calculating...
    if (solution.size() < 4){
        for (int i = 0; i < solution.size(); i++){
            switch (i) {
                case 0:
                    cv::line(bw, cv::Point(solution[i][0], solution[i][1]), cv::Point(solution[i][2], solution[i][3]), ORANGE, 2, 8);
                    break;
                case 1:
                    cv::line(bw, cv::Point(solution[i][0], solution[i][1]), cv::Point(solution[i][2], solution[i][3]), TURQUOISE, 2, 8);
                    break;
                case 2:
                    cv::line(bw, cv::Point(solution[i][0], solution[i][1]), cv::Point(solution[i][2], solution[i][3]), LIGHT_BLUE, 2, 8);
                    break;
                case 3:
                    cv::line(bw, cv::Point(solution[i][0], solution[i][1]), cv::Point(solution[i][2], solution[i][3]), VIOLET, 2, 8);
                    break;
                default:
                    break;
            }
        }
    }
    
    
    // analysis
    if (restart == testCyclesLimit) cout << "Time Limit Reached: " << restart << " cycles." << endl;
    
    // Discussion: Is this transformation going to be required for every frame?
    // I am guessing yes because the laser will probably be more accurate like that. No citations as of yet.
    if (solution.size() == 4){
        
        ready = true;
        
        // we can go ahead and detect intersections now...
        cv::Point2f nw = computeIntersect(west.averaged(), north.averaged());
        cv::Point2f ne = computeIntersect(north.averaged(), east.averaged());
        cv::Point2f sw = computeIntersect(south.averaged(), west.averaged());
        cv::Point2f se = computeIntersect(south.averaged(), east.averaged());
        
        // Draw corner points (unseen unless zoom is off)
        bool cornerPoints = false;
        if (cornerPoints){
            cv::circle(bw, nw, 3, CYAN, 2);
            cv::circle(bw, ne, 3, LIGHT_GREEN, 2);
            cv::circle(bw, sw, 3, LIGHT_BLUE, 2);
            cv::circle(bw, se, 3, VIOLET, 2);
        }
        
        bool manual = false;
        int rows;
        int columns;
        
        if (manual){
            rows = 1080;
            columns = 1920;
        }
        else {
            rows = bw.rows;
            columns = bw.cols;
        }
        
        // prepare array to define landing point of perspective transform
        std::vector<cv::Point2f> quad_pts;
        quad_pts.push_back(cv::Point2f(0, 0)); //nw
        quad_pts.push_back(cv::Point2f(columns, 0)); //ne
        quad_pts.push_back(cv::Point2f(columns, rows)); //se
        quad_pts.push_back(cv::Point2f(0, rows)); //sw
        
        // assemble corner points into an array
        std::vector<cv::Point2f> corners = { nw, ne, se, sw};
        
        // apply the transform to canvas
        if (corners.size() == 4){
            cv::Mat transmtx = cv::getPerspectiveTransform(corners, quad_pts);
            cv::warpPerspective(bw, bw, transmtx, bw.size());  
        }
        
        // every so often reset the test after displaying the appropriate statistics
        if (summary){
            
            cout << "Calculated in " << restart << " cycles..." << endl;

            summary = false;

            cout << "Solution: (" << corners[0].x << "," << corners[0].y << ") ("
            << corners[1].x << "," << corners[1].y << ") ("
            << corners[2].x << "," << corners[2].y << ") ("
            << corners[3].x << "," << corners[3].y << ")\n" << endl;
        }
        
        if (restart >= testCyclesLimit){
            restartDetection();
        }
    }
    
    restart += 1;
    return bw;
};
