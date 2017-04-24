#!/bin/sh
######## Purpose:  Populate the JSS database with user information.

# This is a magic number, it is used to define the percentage of ownership required to decide ownership.   
acceptablelevel=60

# We need a minimum number of logins in total to assume ownership.  This is that number.  AcceptableLevel percent of the number below will trigger ownership assignment 
minLoginCount=35

# Domain name for AD lookups.  
domain="DOMAIN"

#####################################################
#Get list of historical logins and then count them
loginHistoryList=$(cat /var/log/jamf.log |grep "Informing the JSS about login for user"|awk '{print $NF}' |grep -v root)
#loginHistoryList=`last -200 |cut -d " " -f1 |grep -v reboot |grep -v shutdown|grep -v serviceaccount`
loginHistoryCount=$(echo "$loginHistoryList" | wc -l)
echo "Total Logins is $loginHistoryCount"

#Exit if not enough total logins to assume ownership.  
if [ $loginHistoryCount -lt $minLoginCount ]; then
    echo "Not enough total logins to assume ownership.  Closing"
    exit 0
fi


# Count users and logins.  If one is over $acceptableLevel, then assign as main user. 
userList=$(echo "$loginHistoryList" | sort -u)
userListArray=($userList)
for oneUser in "${userListArray[@]}";do
    numLogins=$(echo "$loginHistoryList" | grep $oneUser| wc -l)

    ### Now we do some math to find out what percentage the logins are of all the logins. 
    # Since BASH doesn't do decimals natively, we'll call on the bc to do the work. 
    UserLoginPercent=$(echo "scale=2;$numLogins / $loginHistoryCount * 100" |bc | cut -d '.' -f1)
    echo "$oneUser has $UserLoginPercent% of logins"
    #if this user has most logins, this is our primary user.
    if [ $UserLoginPercent -gt $acceptablelevel ];then
        mainUserFound=$oneUser
    fi
done

if [ -z $mainUserFound ]; then
    echo "no main user found. Over $minLoginCount above, but no user got above $acceptablelevel percent of logins."
    exit 0
fi

echo "Primary User assigned to: $mainUserFound"

userID=`id -u $mainUserFound`

if [ "$userID" -gt 11050 ]; then
    echo "Userid $userID is AD user"
    userFirstname=`/usr/bin/dscl /Active\ Directory/$domain/All\ Domains -read /Users/$mainUserFound FirstName | cut -d " " -f2 2>/dev/null`
    userLastname=`/usr/bin/dscl /Active\ Directory/$domain/All\ Domains -read /Users/$mainUserFound LastName | cut -d " " -f2 2>/dev/null`
    userEmail=`/usr/bin/dscl /Active\ Directory/$domain/All\ Domains -read /Users/$mainUserFound EMailAddress | cut -d " " -f2 2>/dev/null`
    userPhone=`/usr/bin/dscl /Active\ Directory/$domain/All\ Domains -read /Users/$mainUserFound telephoneNumber | cut -d " " -f2 2>/dev/null`
    userDepartment=`/usr/bin/dscl /Active\ Directory/$domain/All\ Domains -read /Users/$mainUserFound profitCenter | cut -d " " -f2 2>/dev/null`
    userRoom=`/usr/bin/dscl /Active\ Directory/$domain/All\ Domains -read /Users/$mainUserFound physicalDeliveryOfficeName | cut -d " " -f2 2>/dev/null`
    userBuilding=$(echo $userRoom | cut -d "-" -f1)

    titleLong=`dscl /Active\ Directory/$domain/All\ Domains -read /Users/$mainUserFound title|tail -1`
    if [[ $titleLong == *":"* ]]; then    #if contains colons, else do the below  
        titleShort=`echo $titleLong |awk -F: '{print $3}'`
    else
        titleShort=$titleLong
    fi
    userPosition=`echo $titleShort | xargs`  #pipe to xargs to remove leading space  

    echo "Submitting information for network account $mainUserFound..."
    echo "$userFirstname"
    echo "$userLastname"
    echo "$userEmail"
    echo "$userPosition"
    echo "$userPhone"
    echo "$userDepartment"
    echo "$userRoom"
    echo "$userBuilding"

    if [ -z $userFirstname ] || [ -z $userLastname ] || [ -z $userDepartment ] ||[ -z $userEmail ]; then
        echo "running recon-lite for user $mainUserFound"
        jamf recon -endUsername "$mainUserFound"
    else
        echo "running recon full for user $mainUserFound"
        jamf recon -endUsername "$mainUserFound" -realname "$userFirstname $userLastname" -email "$userEmail" -position "$userPosition" -phone "$userPhone" -department "$userDepartment" -room "$userRoom" -building "\
$userBuilding"
    fi


else   #if UID less than 1k, then local account 
    jamf recon -position "Local Account"
fi

