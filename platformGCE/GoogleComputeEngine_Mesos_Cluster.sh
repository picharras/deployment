# This starts multiple ubuntu instances using google compute engine and then
# starts a Mesos cluster on them.
#
# Use -r to permanently remove an existing cluster and all machine instances.
#
# Prerequisites:
# The following environment variables are used:
#   PROJECT : project id of your designated project (e.g. -p "project_id");
#
# Optional prerequisites:
#   ZONE           : zone of the server (e.g. -z europe-west1-b)
#   MACHINE_TYPE   : size/machine-type of the instances (e.g. -m n1-standard-4)
#   NUMBER         : count of machines to create (e.g. -n 3)
#   OUTPUT         : local output log folder (e.g. -d /my/directory)

if [ platformGCE/GoogleComputeEngine_Mesos_Cluster.sh -nt ./GoogleComputeEngine_Mesos_Cluster.sh ] || [ Ubuntu/MesosClusterOnUbuntu.sh -nt ./GoogleComputeEngine_Mesos_Cluster.sh ] ; then
  echo 'You almost certainly have forgotten to say "make" to assemble this'
  echo 'script from its parts in subdirectories. Stopping.'
  exit 1
fi

trap "kill 0" SIGINT

ZONE="europe-west1-b"
MACHINE_TYPE="n1-standard-4"
NUMBER="3"
OUTPUT="gce"
PROJECT=""
SSH_KEY_PATH=""
DEFAULT_KEY_PATH="$HOME/.ssh/google_compute_engine"

function deleteMachine () {
  echo "deleting machine $PREFIX$1"
  id=${SERVERS_IDS_ARR[`expr $1 - 1`]}

  gcloud compute instances delete "$id" --zone "$ZONE" -q
}

GoogleComputeEngineDestroyMachines() {

    if [ ! -e "$OUTPUT" ] ;  then
      echo "$0: directory '$OUTPUT' not found"
      exit 1
    fi

    . $OUTPUT/clusterinfo.sh

    declare -a SERVERS_IDS_ARR=(${SERVERS_IDS[@]})

    NUMBER=${#SERVERS_IDS_ARR[@]}

    echo "NUMBER OF MACHINES: $NUMBER"
    echo "OUTPUT DIRECTORY: $OUTPUT"
    echo "MACHINE PREFIX: $PREFIX"


    gcloud compute firewall-rules delete "${PREFIX}firewall"

    for i in `seq $NUMBER`; do
      deleteMachine $i &
    done

    wait

    read -p "Delete directory: '$OUTPUT' ? [y/n]: " -n 1 -r
      echo
    if [[ $REPLY =~ ^[Yy]$ ]]
      then
        rm -r "$OUTPUT"
        echo "Directory deleted. Finished."
      else
        echo "For a new cluster instance, please remove the directory or specifiy another output directory with -d '/my/directory'"
    fi

    exit 0
}

REMOVE=0

while getopts ":z:m:n:d:p:s:hr" opt; do
  case $opt in
    h)
       cat <<EOT
This starts multiple ubuntu instances using google compute engine and then
starts a Mesos cluster on them.

Use -r to permanently remove an existing cluster and all machine instances.

Prerequisites:
The following environment variables are used:
  PROJECT : project id of your designated project (e.g. -p "project_id");

Optional prerequisites:
  ZONE           : zone of the server (e.g. -z europe-west1-b)
  MACHINE_TYPE   : size/machine-type of the instance (e.g. -m n1-standard-4)
  NUMBER         : count of machines to create (e.g. -n 3)
  OUTPUT         : local output log folder (e.g. -d /my/directory)
EOT
      exit 0
      ;;
    z)
      ZONE="$OPTARG"
      ;;
    m)
      MACHINE_TYPE="$OPTARG"
      ;;
    n)
      NUMBER="$OPTARG"
      ;;
    d)
      OUTPUT="$OPTARG"
      ;;
    p)
      PROJECT="$OPTARG"
      ;;
    s)
      SSH_KEY_PATH="$OPTARG"
      ;;
    r)
      REMOVE=1
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

PREFIX="mesos-test-$$-"

echo "OUTPUT DIRECTORY: $OUTPUT"
echo "ZONE: $ZONE"

if test -z "$PROJECT";  then

  #check if project is already set
  project=`gcloud config list | grep project`

  if test -z "$project";  then
    echo "$0: you must supply a project with '-p' or set it with gcloud config set project 'project-id'"
    exit 1
  else
    echo "gcloud project already set."
  fi

else
  echo "Setting gcloud project attribute"
  gcloud config set project "$PROJECT"
fi

if test -z "$ZONE";  then

  #check if project is already set
  zone=`gcloud config list | grep zone`

  if test -z "$zone";  then
    echo "$0: you must supply a zone with '-z' or set it with gcloud config set zone 'your-zone'"
    exit 1
  else
    echo "gcloud zone already set."
  fi

else
  echo "Setting gcloud zone attribute"
  gcloud config set compute/zone "$ZONE"
fi

if test -e "$OUTPUT";  then
  if [ "$REMOVE" == "1" ] ; then
    GoogleComputeEngineDestroyMachines
    exit 0
  fi

  echo "$0: refusing to use existing directory '$OUTPUT'"
  exit 1
fi

if [ "$REMOVE" == "1" ] ; then
  echo "$0: did not find an existing directory '$OUTPUT'"
  exit 1
fi

echo "MACHINE_TYPE: $MACHINE_TYPE"
echo "NUMBER OF MACHINES: $NUMBER"
echo "MACHINE PREFIX: $PREFIX"

LASTSERVER=`expr $NUMBER - 1`
echo LASTSERVER=${LASTSERVER}
mkdir -p "$OUTPUT/temp"

#export CLOUDSDK_CONFIG="$OUTPUT/gce"

if [[ -s "$HOME/.ssh/google_compute_engine" ]] ; then
  echo "GCE SSH-Key existing."
else
  echo "No GCE SSH-Key existing. Creating a new SSH-Key."
  gcloud compute config-ssh
fi ;

#check if ssh agent is running
if [ -n "${SSH_AUTH_SOCK}" ]; then
    echo "SSH-Agent is running."

    #check if key already added to ssh agent
    if ssh-add -l | grep $DEFAULT_KEY_PATH > /dev/null ; then
      echo SSH-Key already added to SSH-Agent;
    else
      ssh-add "$DEFAULT_KEY_PATH"
    fi

  else
    echo "No SSH-Agent running. Skipping."
fi

#add firewall rule for mesos-test tag
echo "Setting up a firewall rule for the cluster..."
gcloud compute firewall-rules create "${PREFIX}firewall" --allow tcp:22,tcp:5050,tcp:8080,tcp:8181,tcp:2181,tcp:31000-31999 --target-tags "${PREFIX}tag"
# FIXME: Remove zookeeper and the ArangoDB framework later on

if [ $? -eq 0 ]; then
  echo
else
  echo Your gcloud settings are not correct. Exiting.
  exit 1
fi

function createMachine () {
  echo "creating machine $PREFIX$1"
  INSTANCE=`gcloud compute instances create --image ubuntu-15-04 --zone "$ZONE" \
            --tags "${PREFIX}tag" --machine-type "$MACHINE_TYPE" \
            "$PREFIX$1" --local-ssd device-name=local-ssd \
            | grep "^$PREFIX"`

  a=`echo $INSTANCE | awk '{print $4}'`
  b=`echo $INSTANCE | awk '{print $5}'`

  echo $a > "$OUTPUT/temp/INTERNAL$1"
  echo $b > "$OUTPUT/temp/EXTERNAL$1"
}

#Ubuntu PARAMS
declare -a SERVERS_EXTERNAL_GCE
declare -a SERVERS_INTERNAL_GCE
declare -a SERVERS_IDS_GCE

SSH_USER="ubuntu"
SSH_CMD="ssh"

for i in `seq $NUMBER`; do
  createMachine $i &
  sleep 1
done

wait

while :
do

  FINISHED=0

  for i in `seq $NUMBER`; do

    if [ -s "$OUTPUT/temp/INTERNAL$i" ] ; then
      echo "Machine $PREFIX$i finished"
      SERVERS_INTERNAL_GCE[`expr $i - 1`]=`cat "$OUTPUT/temp/INTERNAL$i"`
      SERVERS_EXTERNAL_GCE[`expr $i - 1`]=`cat "$OUTPUT/temp/EXTERNAL$i"`
      SERVERS_IDS_GCE[`expr $i - 1`]=$PREFIX$i
      FINISHED=1
    else
      echo "Machine $PREFIX$i not ready yet."
      FINISHED=0
      break
    fi

  done

  if [ $FINISHED == 1 ] ; then
    echo "All machines are set up"
    break
  fi

  sleep 1

done

rm -rf $OUTPUT/temp

echo Internal IPs: ${SERVERS_INTERNAL_GCE[@]}
echo External IPs: ${SERVERS_EXTERNAL_GCE[@]}
echo IDs         : ${SERVERS_IDS_GCE[@]}

echo Remove host key entries in ~/.ssh/known_hosts...
for ip in ${SERVERS_EXTERNAL_GCE[@]} ; do
  ssh-keygen -f ~/.ssh/known_hosts -R $ip
done

echo Testing whether ssh is working...
for i in `seq 0 $LASTSERVER` ; do
    ip=${SERVERS_EXTERNAL_GCE[$i]}
    echo Testing ssh service for $ip...
    until ssh -o"StrictHostKeyChecking no" ubuntu@$ip echo Working
    do
        echo "  not yet working, retrying in 1s."
        sleep 1
    done
done

# Prepare local SSD drives:

# First we need two scripts:
cat <<EOF >$OUTPUT/prepareSSD.sh
#!/bin/bash
parted -s /dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd mklabel msdos
parted -s /dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd mkpart primary "linux-swap(v1)" "0%" "20%"
parted -s /dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd mkpart primary "ext4" "20%" "100%"
sleep 3
mkswap /dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd-part1
mkfs -t ext4 -F -F /dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd-part2
EOF
chmod 755 $OUTPUT/prepareSSD.sh

cat <<EOF >$OUTPUT/mountSSD.sh
#!/bin/bash
echo "/dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd-part1 none swap defaults 0 0" >> /etc/fstab
swapon -a
if [ ! -d /data ] ; then
    mkdir /data
fi
echo "/dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd-part2 /data ext4 defaults 0 0" >> /etc/fstab
mount -a
chown ubuntu.ubuntu /data
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
EOF
chmod 755 $OUTPUT/mountSSD.sh

echo "Preparing machines (parallel)..."
for i in `seq 0 $LASTSERVER` ; do
    ip=${SERVERS_EXTERNAL_GCE[$i]}
    echo Preparing machine $ip...
    scp -o"StrictHostKeyChecking no" $OUTPUT/prepareSSD.sh $OUTPUT/mountSSD.sh ubuntu@$ip:
    ssh -o"StrictHostKeyChecking no" ubuntu@$ip "sudo ./prepareSSD.sh && sudo ./mountSSD.sh" &
done

wait
SERVERS_INTERNAL="${SERVERS_INTERNAL_GCE[@]}"
SERVERS_EXTERNAL="${SERVERS_EXTERNAL_GCE[@]}"
SERVERS_IDS="${SERVERS_IDS_GCE[@]}"

# Export needed variables
export SERVERS_INTERNAL
export SERVERS_EXTERNAL
export SERVERS_IDS
export SSH_USER="ubuntu"
export SSH_CMD="ssh"
export SSH_SUFFIX="-i $DEFAULT_KEY_PATH"
export OUTPUT

# Write data to file:
echo > $OUTPUT/clusterinfo.sh "SERVERS_INTERNAL=\"$SERVERS_INTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_EXTERNAL=\"$SERVERS_EXTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_IDS=\"$SERVERS_IDS\""
echo >>$OUTPUT/clusterinfo.sh "SSH_USER=\"$SSH_USER\""
echo >>$OUTPUT/clusterinfo.sh "SSH_CMD=\"$SSH_CMD\""
echo >>$OUTPUT/clusterinfo.sh "SSH_SUFFIX=\"$SSH_SUFFIX\""
echo >>$OUTPUT/clusterinfo.sh "PREFIX=\"$PREFIX\""
echo >>$OUTPUT/clusterinfo.sh "ZONE=\"$ZONE\""
echo >>$OUTPUT/clusterinfo.sh "PROJECT=\"$PROJECT\""

startMesosClusterOnUbuntu
