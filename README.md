Instructions

Note: Please configure the Java version in your local environment which needs to be >=1.7

1) Download apache jmeter 3.1
	
2) Copy jars from lib folder into jmeter lib/ext folder

3) Install Docker

4) Download the available MFinPlus image from fileserver/MFin Releases/MFin Plus Docker Image and import 
   docker  load < syntech-mfindev-v2.24.0.tar 
Or

 Build the  mfinplus docker image from server-config repo

5) Run the mfin plus image
   docker run -it --rm --name syntech-mfindev -p 8048:8048 -p 8080:8080 "syntech-mfindev:v2.24.0" (Note : version may change, confirm you have the target image by running docker container ls --all )

6) Make a softlink of jmeter to /usr/local/bin folder (if jmeter can't be found inside $PATH)
   Command : sudo ln -s /opt/apache-jmeter-3.1/bin/jmeter.sh /usr/local/bin/jmeter
(Note : Folder location may vary depending where Jmeter is placed)

7) Clone a repository of Mercurial server with repository name mfinplus-testing
   ssh://hg@dev.synergytechsoft.com:5022/mfinplus-testing

Note: Package environment required for running this script 
   a) curl : To download this in linux use the following command
	sudo apt-get install curl
	 
8) Go to mfinplus-testing/DockerTest and run runTest.sh (Note: Use linux environment) 
   #Change directory 
   i) cd mfinplus-testing/DockerTest

   # For running all scripts at once
   ii) bash runTest.sh

   #For running directory wise TestCases 
   iii) bash runTest.sh -d TestCases/LoanEdit

   #For giving separate path to check the result
   iv) bash runTest.sh -o FullTestV2.26.0 -d TestCases/LoanEdit

   #For giving test case name
   v) bash runTest.sh -t loanEdit

9) To view Test Results, log files, test reports open Output folder 
   Multiple *.jtl files  generated inside Output folder contains test results.
   To verify the test case result if it passes or fail we need to check "aggregateresult.csv".
   The test case id which is validated from webservice and message is obtained which has value in success column "true" or "false".
   HTML jmeter output can be found inside the Output folder under the timestamp
