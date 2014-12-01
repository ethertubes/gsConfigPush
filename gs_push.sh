#!/bin/bash

#  +----------------------------------------------------------------------+
#  | Grandstream GXP21xx IP Phone HTTP POSTing P-value config pusher      |
#  | May work with with other Grandstream devices, use at your own risk.  |
#  +----------------------------------------------------------------------+
#  | For the latest P-value descriptions consult the applicatble firmware |
#  | release notes and configuration template descriptions:               |
#  | http://www.grandstream.com/tools/GAPSLITE/config-template.zip        |
#  +----------------------------------------------------------------------+
#  | The contents of this file are subject to the General Public License  |
#  | (GPL) Version 2 (the "License"); you may not use this file except in |
#  | compliance with the License. You may obtain a copy of the License at |
#  | http://www.opensource.org/licenses/gpl-license.php                   |
#  |                                                                      |
#  | Software distributed under the License is distributed on an "AS IS"  |
#  | basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See  |
#  | the License for the specific language governing rights and           |
#  | limitations under the License.                                       |
#  +----------------------------------------------------------------------+


get_password () {
        saveIFS="$IFS"
        IFS=$'\n'
        while read -s -n 1 char
        do
                case $(printf "%d\n" \'$char) in

                127)
                        if [ "${#passwd}" -gt 0 ]; then
                                echo -ne "\b \b"
                                passwd="${passwd:0:${#passwd}-1}"
                        fi
                        ;;
                0)
                        echo
                        break
                        ;;
                *)
                        echo -n "*"
                        passwd+=$char
                esac
        done
        IFS=$saveIFS
}

target_ip="$1"
if [ -z "$target_ip" ]; then
	echo "Usage: $0 <IP Address of Grandstream device> [P-value pairs] [password]" >&2
	exit 1
fi

Pvalues="$2"
passwd="$3"

if [ -z "$passwd" ]; then
	# If the second argument isn't a valid P-code pair use it as the password
	if [ "${Pvalues//'='}" == "$Pvalues" ]; then
		passwd="$Pvalues"
		unset Pvalues
	fi
fi
if [ -z "$passwd" ]; then
		echo -n "Enter password [admin]: "
		get_password
		if [ -z "$passwd" ]; then
			passwd="admin"
		fi
fi

if [ -z "$Pvalues" ]; then
	# See if anything is waiting on stdin
	read -t1 Pvalues
	if [ -z "$PValues" ]; then
		# Or just ask the user..
		echo "Enter the P-code and value pair. Use '&' to separate multiple P-values."
		echo "Example: P330=3&P331=10.0.0.1/phonebook.xml&P332=30&P333=1"
		echo -n "P-values: "
		read Pvalues
	fi
fi

get_sid() {
	while read -r || [[ -n "$REPLY" ]]
	do
		if [ -n "$sid" ]; then
			break
		fi
		if [ "${REPLY:0:23}" == "Set-Cookie: session_id="  ]; then
			sid="${REPLY:23}"
			sid="${sid//;}"
		fi
		if [ "${REPLY//'"sid"'}" != "$REPLY" ]; then
			sid="${REPLY#*'"sid"'}"
			sid="${sid#*'"'}"
			sid="${sid%%'"'*}"
		fi
		
	done
	echo "$sid"
}


post_status() {
	# Old firmware says need to reboot, new firmware says success
	# new firmware doesn't end with a line break :(
	while read -r || [[ -n "$REPLY" ]]
        do
                if [ "${REPLY//eboot}" != "$REPLY" ]; then
                        echo "1"
                        break
                fi
                if [ "${REPLY//success}" != "$REPLY" ]; then
                        echo "1"
                        break
                fi
        done
}

reboot_status() {
	success=0
	headers=0
	while read -r || [[ -n "$REPLY" ]]
	do	
		if [ -z "$REPLY" ]; then
			# header data done
			headers=1
		fi
		if [ "${REPLY//'{"results":['}" != "$REPLY" ]; then
			if [ "${REPLY//[1]}" != "$REPLY" ]; then
				success=1
			fi
			break
		fi
		if [ "${REPLY//'savereboot'}" != "$REPLY" ]; then
			success=1
			break
		fi
		if [ "${REPLY//'relogin'}" != "$REPLY" ]; then
			success=1
			break
		fi
		# fw 1.0.1.56 requires a different reboot action
		if [ "${REPLY//'The requested URL was not found'}" != "$REPLY" ]; then
			curl -s -i -b "session_id=$sid" "http://$target_ip/cgi-bin/rs" |reboot_status
			unset REPLY
			success=2
		fi

		# print extra saving info mixed in the headers, but ignore other bits
		if [ "${REPLY//:}" != "$REPLY" ]; then
			unset REPLY
		fi
		if [ "${REPLY:0:4}" == "HTTP" ]; then
			unset REPLY
		fi
		if [ "${REPLY:0:1}" == "<" ]; then
			unset REPLY
		fi
		if [ "$headers" == "0" ] && [ -n "$REPLY" ]; then
			echo "$REPLY"
		fi
		
	done
	if [ "$success" == "1" ]; then
		echo "Success!"
	fi
	if [ "$success" == "0" ]; then
		echo "Fail. ($target_ip)" >&2
	fi
}


if [ -z "$Pvalues" ]; then
	echo "No configuration parameters specified." >&2
	exit 1
fi

# Older firmware passed password as "P2", newer firmware passes as "password"
# <form> action is the same
sid="$(curl -s -i -d "P2=$passwd&password=$passwd" "http://$target_ip/cgi-bin/dologin" |get_sid)"

if [ -z "$sid" ]; then
	echo "Login failed." >&2
	exit 1
fi

# <form> action for config update is different across firmware versions
# Try old firmware style first
status="$(curl -s -i -b "session_id=$sid" -d "$Pvalues&update=Update" "http://$target_ip/cgi-bin/update" |post_status)"

if [ -z "$status" ]; then
	# Try new firmware config update action
	status="$(curl -s -i -b "session_id=$sid" -d "sid=$sid&$Pvalues" "http://$target_ip/cgi-bin/api.values.post" |post_status)"
fi

# Try new firmware way if the last attempt failed
if [ -n "$status" ]; then
	echo "Config sent, rebooting..."
	# Old firmware used query_string to pass REBOOT, new firmware uses POST data
	curl -s -i -d "request=REBOOT&sid=$sid" -b "session_id=$sid" "http://$target_ip/cgi-bin/api-sys_operation?REBOOT" |reboot_status
else
	echo "Couldn't update configuration ($target_ip)" >&2
fi
