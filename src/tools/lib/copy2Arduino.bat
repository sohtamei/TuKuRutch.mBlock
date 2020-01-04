rmdir                ..\..\Arduino\portable\sketchbook\libraries\quadCrawlerLib\  /S /Q
rmdir                ..\..\Arduino\portable\sketchbook\libraries\remoconRoboLib\  /S /Q

xcopy quadCrawlerLib ..\..\Arduino\portable\sketchbook\libraries\quadCrawlerLib\  /S /Q /Y
xcopy remoconRoboLib ..\..\Arduino\portable\sketchbook\libraries\remoconRoboLib\  /S /Q /Y
pause
