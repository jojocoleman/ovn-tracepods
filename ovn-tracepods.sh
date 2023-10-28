# Title:                    ovn-tracepods.sh
# Creator:                  John Coleman
# Creation Date:            10/25/2023
# Modification Date:        10/27/2023
# Desscription:             
# A tool to simplify ovn-trace.  The script also allows users to specify sets 
# of source and destination pods by which the script will find, and test ovn
# path from n source pods to n destination pods.
# Tool is meant to be run from Linux box that is logged into an Openshift 4 cluster
# using the OVNKubernetes CNI plugin.  
#
# Progress:                 Work in progress.


# This is a debugging tool provided without warranty. It offers no support from Red Hat or any other official source. Please use at your own risk.


#! /bin/bash

trap signal EXIT
trap signal SIGINT

function signal()
{
	echo "Received signal so exiting."
	exit
}


function setup_var()
{
	echo "Enter source pod namespace: "
	read SRCNS
	echo "Enter destination pod namespace: "
	read DSTNS
	echo "Enter source deployment name: "
	read SRCDEP
	echo "Enter destination deployment name: "
	read DSTDEP
	echo "Enter protocol (tcp|udp): "
	read PROTO
	echo "Enter source port number (optional): "
	read SRCPORT
	echo "Enter destination port number: "
	read DSTPORT
	echo "Specify IP TTL (if not sure, enter 64): "
	read TTL

	SRCPOD_ARRAY=($(oc get pods -n ${SRCNS} | grep ${SRCDEP} | awk '{print $1}'))
	SRCPOD_COUNT=$(oc get pods -n ${SRCNS} | grep ${SRCDEP} | wc -l)
	DSTPOD_ARRAY=($(oc get pods -n ${DSTNS} | grep ${DSTDEP} | awk '{print $1}'))
	DSTPOD_COUNT=$(oc get pods -n ${DSTNS} | grep ${DSTDEP} | wc -l)
}

function sbdb_leader()
{
	SBDBLEADER=$(for OVNMASTER in $(oc -n openshift-ovn-kubernetes get pods -l app=ovnkube-master -o custom-columns=NAME:.metadata.name --no-headers)
	do 
		if [[ $(echo `oc -n openshift-ovn-kubernetes rsh -Tc northd $OVNMASTER ovn-appctl -t /var/run/ovn/ovnsb_db.ctl cluster/status OVN_Southbound | grep ^Role`) == "Role: leader" ]]
		then 
			echo ${OVNMASTER}
		fi
	done)
}

function trace()
{
	sbdb_leader
	for SRCPOD in ${SRCPOD_ARRAY[*]}
	do
		echo "Setting up source pods."
		NODE=$(oc get pod ${SRCPOD} -n ${SRCNS} -o custom-columns='NODE:.spec.nodeName' | awk 'NR>1')
		OVNKMASTER=($(oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-master --no-headers -o custom-columns='POD:.metadata.name'))
		SRCADDRS=($(oc exec -it ${OVNKMASTER[0]} -n openshift-ovn-kubernetes -c northd -- /bin/bash -c "ovn-nbctl --no-leader-only find Logical_Switch_Port name=${SRCNS}_${SRCPOD}" | grep "^addresses" | awk -F '[' '{print $2}' | tr -d \"]))
		SRCMAC=${SRCADDRS[0]}
		SRCIP=${SRCADDRS[1]}

		for DSTPOD in ${DSTPOD_ARRAY[*]}
		do
			echo "Setting up destination pods."
			DSTADDRS=($(oc exec -it ${OVNKMASTER[0]} -n openshift-ovn-kubernetes -c northd -- /bin/bash -c "ovn-nbctl --no-leader-only find Logical_Switch_Port name=${DSTNS}_${DSTPOD}" | grep "^addresses" | awk -F '[' '{print $2}' | tr -d \"]))
			DSTMAC=${DSTADDRS[0]}
			DSTIP=${DSTADDRS[1]}
			if [[ -n "${SRCPORT}" ]]
			then
				echo "==================================="
        echo "Source pod      =	${SRCPOD}"
				echo "Source node     = 	${NODE}"
				echo "Destination pod = 	${DSTPOD}"
				echo "==================================="
				echo ""
				echo "Executing trace with source port."
				oc exec -it ${SBDBLEADER} -n openshift-ovn-kubernetes -c northd -- /bin/bash -c "ovn-trace --ct new ${NODE} 'inport==\"${SRCNS}_${SRCPOD}\" && eth.src==${SRCMAC} && eth.dst==${DSTMAC} && ${PROTO} && ${PROTO}.src==${SRCPORT} && ${PROTO}.dst==${DSTPORT} && ip4.src==${SRCIP} && ip4.dst==${DSTIP} && ip.ttl==${TTL}'"

			else
        echo ""
        echo "==================================="
        echo "Source pod      =	${SRCPOD}"
        echo "Source node     =         ${NODE}"
        echo "Destination pod =         ${DSTPOD}"
        echo "==================================="
        echo ""
				echo "Executing trace without source port."
				oc exec -it ${SBDBLEADER} -n openshift-ovn-kubernetes -c northd -- /bin/bash -c "ovn-trace --ct new ${NODE} 'inport==\"${SRCNS}_${SRCPOD}\" && eth.src==${SRCMAC} && eth.dst==${DSTMAC} && ${PROTO} && ${PROTO}.dst==${DSTPORT} && ip4.src==${SRCIP} && ip4.dst==${DSTIP} && ip.ttl==${TTL}'"
			fi
		done
	done
}

# TODO:
# Set up this function to be called if the above fails
# Should print environment variables to ensure they are being added correctly
# I will eventually include more debugging tools, for this script as I continue testing.
function debug()
{
	echo ""
	echo "DEBUG:"
	echo -e "${SBDBLEADER}\n${NODE}\n${SRCNS}\n${SRCPOD}\n${SRCMAC}\n${DSTMAC}\n${PROTO}\n${SRCPORT}\n${DSTPORT}\n${SRCIP}\n${DSTIP}\n${TTL}\n"
	echo ""
}

function main()
{
	echo "Program initialized."
	setup_var
	trace
}

main
