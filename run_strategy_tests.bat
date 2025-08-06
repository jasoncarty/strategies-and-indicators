@echo off
echo Starting automated strategy testing...

start /wait "" "C:\Program Files\MetaTrader 5\terminal64.exe" /tester:SimpleBreakoutML_EA.ex5,GBPUSD+,H1,2023.01.01,2024.12.31,genetic,10000,USD /export:SimpleBreakoutML_EA\GBPUSD+_H1_20250730_202917
echo Completed test for GBPUSD+ H1

start /wait "" "C:\Program Files\MetaTrader 5\terminal64.exe" /tester:SimpleBreakoutML_EA.ex5,GBPUSD+,M15,2023.01.01,2024.12.31,genetic,10000,USD /export:SimpleBreakoutML_EA\GBPUSD+_M15_20250730_202917
echo Completed test for GBPUSD+ M15

start /wait "" "C:\Program Files\MetaTrader 5\terminal64.exe" /tester:SimpleBreakoutML_EA.ex5,USDJPY+,H1,2023.01.01,2024.12.31,genetic,10000,USD /export:SimpleBreakoutML_EA\USDJPY+_H1_20250730_202917
echo Completed test for USDJPY+ H1

start /wait "" "C:\Program Files\MetaTrader 5\terminal64.exe" /tester:SimpleBreakoutML_EA.ex5,USDJPY+,M15,2023.01.01,2024.12.31,genetic,10000,USD /export:SimpleBreakoutML_EA\USDJPY+_M15_20250730_202917
echo Completed test for USDJPY+ M15

start /wait "" "C:\Program Files\MetaTrader 5\terminal64.exe" /tester:SimpleBreakoutML_EA.ex5,ETHUSD,H1,2023.01.01,2024.12.31,genetic,10000,USD /export:SimpleBreakoutML_EA\ETHUSD_H1_20250730_202917
echo Completed test for ETHUSD H1

start /wait "" "C:\Program Files\MetaTrader 5\terminal64.exe" /tester:SimpleBreakoutML_EA.ex5,ETHUSD,M15,2023.01.01,2024.12.31,genetic,10000,USD /export:SimpleBreakoutML_EA\ETHUSD_M15_20250730_202917
echo Completed test for ETHUSD M15

start /wait "" "C:\Program Files\MetaTrader 5\terminal64.exe" /tester:SimpleBreakoutML_EA.ex5,USDCAD+,H1,2023.01.01,2024.12.31,genetic,10000,USD /export:SimpleBreakoutML_EA\USDCAD+_H1_20250730_202917
echo Completed test for USDCAD+ H1

start /wait "" "C:\Program Files\MetaTrader 5\terminal64.exe" /tester:SimpleBreakoutML_EA.ex5,USDCAD+,M15,2023.01.01,2024.12.31,genetic,10000,USD /export:SimpleBreakoutML_EA\USDCAD+_M15_20250730_202917
echo Completed test for USDCAD+ M15

echo All tests completed!
pause