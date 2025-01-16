#!/bin/bash -Eeu
#while lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null
#do
#    echo "Waiting for mfin to come up..."
#    sleep 5
#done

# To check the server status as per the config file
MY_PATH="`dirname \"$0\"`"
. $MY_PATH/config.properties

mfinURL="${protocal}://${targetHost}:${targetPort}/${app}"

if !  curl --output /dev/null --silent --head --fail  $mfinURL
then
    echo "The URL $mfinURL is not reachable, please check the config file or status of the docker/server"
    echo "---------------------------------------- Exiting Test-----------------------------------------------------------"
    exit 1
else
    echo "Running integration test for the application running on $mfinURL"
fi

OLDIFS=$IFS
IFS=$'\n'
testCase=""
testCases=()
usage()
{
    echo "Use one of the following options:"
    echo -e "\t-o <output-dir-prefix>"
    echo -e "\t-d <testcase-dir-root>"
    echo -e "\t-t <testcase>"
}

# @todo better way to check inside docker or not 
is_inside_mfinplus_docker()
{

    if [[ -f /tmp/glassfish.passwords && -f /tmp/glassfish-3.1.2.2-silent-installation-answers && -f /.dockerenv ]]; 
    	then 
		return 0; 
	else 
		return 1;
	fi

}

while getopts o:t:d: option
do
        case "${option}"
        in
                o) outputPath=${OPTARG};;
                d) testCasePath=${OPTARG};;
                t) testCase=${OPTARG};;
                \?) usage
                    exit 1;;
        esac
done

command -v jmeter 2>/dev/null >/dev/null
if ! [ $? -eq 0 ]; then 
    echo 'Error: jmeter is not installed or not in PATH'
    exit 1
fi
set -e

# @todo run the scripts and put output in  ./output directory
#echo "outputPath is $outputPath"
today=`date +%Y-%m-%d.%H_%M_%S`
outputPath=${outputPath:-"$PWD/Output"}
outputPrefix=${outputPrefix:-"$today"}
mkdir -p $outputPath
mkdir -p "$outputPath/$outputPrefix"
outputPath="$outputPath/$outputPrefix"
echo "outputPrefix: $outputPrefix"
echo "outputPath: $outputPath"

testCasePath=${testCasePath:-"$PWD/TestCases"}
if [ ! -d ${testCasePath} ]; then
    echo "Error: testCasePath $testCasePath does not exist."
    exit 1
fi
echo "testCasePath: $testCasePath"

if [ -z "${testCase}" ]; then
    testCase="*"
fi
testCases=$(find ${testCasePath} -maxdepth 2 -type f -name "${testCase}.jmx" | sort ) #$(ls ${testCasePath}/${testCase}/*.jmx)
if [ ${#testCases[@]} -lt 1 ]; then #if (( ${#testCases[@]} )); then
    echo "No test cases found"
    exit 0;
fi
#taking backup to restore database after each jmx file run
if  is_inside_mfinplus_docker &&  [ -z "${TEST_FILE}" ]; then mysqldump  --single-transaction -u root -proot mfin_synergy > /tmp/mfin_synergy.sql; fi

#initail temp value
reloadTemp=0
echo "Test cases to run:"
for t in ${testCases[@]}; do
    echo "${t}"
    reloadTemp=$(($reloadTemp+1))
done

#reload application
function reload(){
    response=$( curl -X POST -H "Content-Type: text/plain" --data "select * from global_settings;"  $mfinURL/mfinws/mfinServices/updateGlobalSettings)
    statusCheck=$( curl -X POST -H "Content-Type: text/plain" --data "select * from global_settings;" > /dev/null 2>&1 $mfinURL/mfinws/mfinServices/updateGlobalSettings)
    tempVal1=$(echo $response | sed 's/.*message":"//g' | sed 's/"},"error.*//g')

    if [[ $tempVal1 == "Query executed and application reloaded." && $? -eq 0 ]];then 
        echo "Succesful reloaded"
    else
        echo "Reload failed"
    fi
}


for j in ${testCases[@]}; do
    echo "Testcase: ${j}"
    #Getting the config number from the jmx file pattern and set on conf
    conf=$(echo $j | grep -o '[0-9]*')
    #Remove digit from file name to run the actual jmx file and set on k
    k=$(echo $j | sed 's/[0-9]//g')
    #making folder for exporting html report from jmeter. Jmeter needs each jmx file to have different folders for this report.
    testfile=$(basename -- ${j%.*})	
    mkdir -p "${outputPath}/${testfile}_report"
    start_time=`date +%s`
    # We can set properties on command line with -Jx=y
    CMD="jmeter -Jsample_variables=actual_result,expected_result,caseId,caseName -Jseq=$conf -n -t \"${k}\" -l ${outputPath}/${testfile}_output.jtl -j ${outputPath}/${testfile}.log -e -o ${outputPath}/${testfile}_report -JResult=${outputPath}/result.log"
    eval $CMD
    end_time=`date +%s`
    eval difference${testfile}=$((end_time-start_time))
    #Restoring database initial database such that any data polluted by previous test gets discarded
    if  is_inside_mfinplus_docker && [ -z "${TEST_FILE}" ]; then echo "Restoring database "; mysql -uroot -proot mfin_synergy < /tmp/mfin_synergy.sql; fi
    if [[ $reloadTemp -gt 1 ]];then reload; fi
    
done
if is_inside_mfinplus_docker && [ -n "${TEST_FILE}" ]; then 
	cp /opt/glassfish3/glassfish/domains/domain1/logs/gc.log $outputPath/${TEST_FILE}_gc.log  2>/dev/null || :; 
elif is_inside_mfinplus_docker ; then
	cp /opt/glassfish3/glassfish/domains/domain1/logs/gc.log $outputPath/gc.log  2>/dev/null || :; 
fi
# restore it
IFS=$OLDIFS

if ! ls $outputPath/*.jtl 1> /dev/null 2>&1; then exit 1; fi;

#defining regex_pattern to be check through sed replace
regex_pattern1="||"

#Declaring regex_array
declare -a regex_array

#Assigning regex pattern in an array and if regex_pattern added then add in array
regex_array=($regex_pattern1)

#Writing aggregate result
cat $outputPath/*jtl | sed -e '/timeStamp/d' > $outputPath/temp.csv
cat $outputPath/temp.csv | tr '\n' '|' > $outputPath/temp1.csv

for i in ${regex_array[@]}
do
    sed "s/"$i"//g" $outputPath/temp1.csv > $outputPath/temp.csv
    cat $outputPath/temp.csv>$outputPath/temp1.csv
done

cat $outputPath/temp.csv | tr '|' '\n' > $outputPath/temp1.csv 
head -n 1 $(ls $outputPath/*.jtl | head -n 1) > $outputPath/temp.csv
cat $outputPath/temp1.csv | grep -i "TC_" >>  $outputPath/temp.csv
cut -d, -f1-2,6-7,9-16 --complement $outputPath/temp.csv > $outputPath/aggregrateresult.csv 

PASSED=$(awk -F'"' -v OFS='' '{ for (i=2; i<=NF; i+=2) gsub(",", "", $i) } 1' $outputPath/aggregrateresult.csv | awk -F ','  'BEGIN {OFS=FS=","} { if ($4 == "true")  print $7}')
FAILED=$(awk -F'"' -v OFS='' '{ for (i=2; i<=NF; i+=2) gsub(",", "", $i) } 1' $outputPath/aggregrateresult.csv | awk -F ','  'BEGIN {OFS=FS=","} { if ($4 == "false")  print $7}')
DISTINCT=$(awk -F'"' -v OFS='' '{ for (i=2; i<=NF; i+=2) gsub(",", "", $i) } 1' $outputPath/aggregrateresult.csv | tail -n +2 | cut  -d, -f7  | sort | uniq  -c | wc -l)

echo "Total test runs: $(tail -n +2 $outputPath/aggregrateresult.csv | wc -l ), Passed: $(echo $PASSED | wc -w), Failed: $(echo $FAILED | wc -w), Distinct Test Cases: $DISTINCT"
echo "------------------------Failed Test Cases-------------------------------"
echo $FAILED;

echo "------------------------Passed Test Cases-------------------------------"
echo $PASSED;
rm $outputPath/temp.csv
rm $outputPath/temp1.csv

for j in ${testCases[@]}; do
    testfile=$(basename -- ${j%.*}) 
    temp=difference${testfile}
    printf "\n\nTotal time required to run ${testfile}.jmx: "${!temp}"\n\n"
done
