# path to caffe
# caffe=/home/go/Project/captcha_recognition/code/caffe_new/${1}

# add Cuda Library path (not neccessary if path is set permanent)
#export LD_LIBRARY_PATH=/usr/local/cuda-7.0/targets/x86_64-linux/lib

# get parameters
name=$1
mode=$2
network=$3
network_test=$4
echo "["`date '+%Y-%m-%d %H:%M:%S'`"] ##################### iterate.sh ->  Starting with "$name" in mode "$mode


#maxIter=45
#finalTestingImages=2000
#initialTrainingImages=10000
#learningImagesInEveryIteration=100000
#newTrainingImagesInEveryIteration=10000

maxIter=45
finalTestingImages=2000
initialTrainingImages=10000
learningImagesInEveryIteration=100000
newTrainingImagesInEveryIteration=10000

getNumberOfIters() {
	#calculate iterations
	if [ "$i" -eq 1 ]; then
		# 50,000 iterations for epoch 1
		iters=50000
		iters_previous=0
	elif [ "$i" -le 6 ]; then
		# 25,000 iterations for epoch 2-6
		iters_previous=$iters
		iters=$((iters+25000))
	elif [ "$i" -le 11 ]; then
		# 20,000 iterations for epoch 7-11
		iters_previous=$iters
		iters=$((iters+20000))
	elif [ "$i" -le 16 ]; then
		# 15,000 iterations for epoch 12-16
		iters_previous=$iters
		iters=$((iters+15000))
	elif [ "$i" -le 21 ]; then
		# 10,000 iterations for epoch 17-21
		iters_previous=$iters
		iters=$((iters+10000))
	else
		# 5,000 iterations for epoch > 21
		iters_previous=$iters
		iters=$((iters+5000))
	fi
}


# check if the test had been running before and was killed.
# If the temp folder does not exist, the test with this name was never started before and we start from the beginning 
if [ ! -d "temp/$name" ]; then
	# create temp folder
	mkdir temp/$name
	mkdir temp/${name}/results
	
	# set permissions
	chmod +x src/createdb.sh
	
	# copy solver and network prototxt before we edit them
	cp src/captcha_solver.prototxt temp/${name}/captcha_solver.prototxt
	cp src/${network}.prototxt temp/${name}/${network}.prototxt
	
	# set the snapshot prefix to the $name in the solver file
	sed -i 's/snapshot_prefix: \".*\"/snapshot_prefix: \"temp\/'$name'\/results\/data\"/' temp/${name}/captcha_solver.prototxt
	
	# set the network in the solver file
	sed -i 's/net: \".*\"/net: \"temp\/'$name'\/'${network}'.prototxt"/' temp/${name}/captcha_solver.prototxt
	
	# set the training database in the network file
	sed -i 's/source: \".*\"/source: \"temp\/'$name'\/train_db\"/' temp/${name}/${network}.prototxt
	
	
	# create final testing images
	echo -e "\n["`date '+%Y-%m-%d %H:%M:%S'`"] # iterate.sh ->  Creating final testing images..."
	echo -e "["`date '+%Y-%m-%d %H:%M:%S'`"] php-cgi src/createcoolcaptchas.php folder="$name"/final_val_files amount="$finalTestingImages
	php-cgi src/createcoolcaptchas.php folder=${name}/final_val_files amount=$finalTestingImages
	
	# create inital train images
	echo -e "\n["`date '+%Y-%m-%d %H:%M:%S'`"] # iterate.sh ->  Creating inital training images..."
	echo -e "["`date '+%Y-%m-%d %H:%M:%S'`"] php-cgi src/createcoolcaptchas.php folder="$name"/train_files amount="$initialTrainingImages
	php-cgi src/createcoolcaptchas.php folder=${name}/train_files amount=$initialTrainingImages
	
	# The content of the files Output_accuracy_matlab.txt and Output_learning_accuracy_matlab.txt can be copied directly into Matlab to plot the accuracy
	echo -n "plot ([0" >> results/$name/Output_accuracy_matlab.txt
	echo -n "plot ([0" >> results/$name/Output_learning_accuracy_matlab.txt
	
	startiters=1

# The program was running before and has been interrupted. Continue the execution from the point where it was killed.
else
	# Find the point where the program was killed
	for (( i=1; i<=$maxIter; i++ ))
		do
			getNumberOfIters
			
			# check if this solverstate already exists
			solverstate="temp/"$name"/results/data_iter_"$iters".solverstate"
			if [ -f "$solverstate" ]; then
				echo -e "["`date '+%Y-%m-%d %H:%M:%S'`"] ##################### iterate.sh ->  Continuing from "$solverstate
				startiters=$i
				break
			else
				continue
			fi
		done
fi

echo -e "\n["`date '+%Y-%m-%d %H:%M:%S'`"] =======================================================\nBlok 1. Done"
echo -e "\n["`date '+%Y-%m-%d %H:%M:%S'`"] ##################### iterate.sh ->  Start iteration : "$startiters" and max iteration: "$maxIter

for (( i=$startiters; i<=$maxIter; i++ ))
	do
		getNumberOfIters
		echo -e "\n["`date '+%Y-%m-%d %H:%M:%S'`"] ====== iteration "$i" START ====="
		# create database
		echo -e "\n["`date '+%Y-%m-%d %H:%M:%S'`"] # iterate.sh ->  Creating level database in iteration "$iters"..."
		echo -e "["`date '+%Y-%m-%d %H:%M:%S'`"] ./src/createdb.sh "$name" "$i"\n"
		./src/createdb.sh $name $i
		
		# train the network
		echo -e "\n["`date '+%Y-%m-%d %H:%M:%S'`"] # iterate.sh ->  Training network..."
		echo -e "["`date '+%Y-%m-%d %H:%M:%S'`"] caffe train --solver=temp/"$name"/captcha_solver.prototxt "
		
		sed -i 's/max_iter: [0-9][0-9]*/max_iter: '$iters'/' temp/${name}/captcha_solver.prototxt
		
		if [ "$iters_previous" -gt 0 ]; then
			#${caffe}/build/tools/caffe train --solver=temp/${name}/captcha_solver.prototxt "--snapshot=temp/"$name"/results/data_iter_"$iters_previous".solverstate"
			echo -e "--snapshot=temp/"$name"/results/data_iter_"$iters_previous".solverstate"
			caffe train --solver=temp/${name}/captcha_solver.prototxt "--snapshot=temp/"$name"/results/data_iter_"$iters_previous".solverstate"
		else
			#${caffe}/build/tools/caffe train --solver=temp/${name}/captcha_solver.prototxt
			caffe train --solver=temp/${name}/captcha_solver.prototxt
		fi
		echo -e "\n["`date '+%Y-%m-%d %H:%M:%S'`"] ##################### iterate.sh ->  ... Finished traing.\n"
		
		# create learning images
		echo -e "\n["`date '+%Y-%m-%d %H:%M:%S'`"] # iterate.sh ->  Creating learning images..."
		echo -e "["`date '+%Y-%m-%d %H:%M:%S'`"] php-cgi src/createcoolcaptchas.php folder="$name"/learning_files amount="$learningImagesInEveryIteration
		php-cgi src/createcoolcaptchas.php folder=${name}/learning_files amount=$learningImagesInEveryIteration
		
		# compute accuracy and new train images (for the next iteration)
		echo -e "\n["`date '+%Y-%m-%d %H:%M:%S'`"] # iterate.sh ->  Testing network after "$iters" iterations (and creating new training images for next iteration)..."
		
		#remove the old images
		rm -rf temp/${name}/train_files/
		mkdir temp/${name}/train_files/
		
		echo -e "["`date '+%Y-%m-%d %H:%M:%S'`"] python src/test_network.py "$name" "$iters" "$iters_previous" "$mode" "$newTrainingImagesInEveryIteration" "$network_test
		python src/test_network.py $name $iters $iters_previous $mode $newTrainingImagesInEveryIteration $network_test
		
		echo -e "\n["`date '+%Y-%m-%d %H:%M:%S'`"] ====== iteration "$i" END ====="
		
	done

echo -e "["`date '+%Y-%m-%d %H:%M:%S'`"] =======================================================\nBlok 2. Done"

echo -n "])" >> results/$name/Output_accuracy_matlab.txt
echo -n "])" >> results/$name/Output_learning_accuracy_matlab.txt

#cleanup
#echo -e "\n["`date '+%Y-%m-%d %H:%M:%S'`"] ##################### iterate.sh ->  Cleaning up..."
#rm -rf temp/$name

echo -e "["`date '+%Y-%m-%d %H:%M:%S'`"] ##################### iterate.sh ->  Finished!"
