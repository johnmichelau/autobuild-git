#!/usr/bin/env bash

# git-autobuild.sh
#   This script is intended as a bare-bones replacement for a Jenkins continuous
#   integration job.  It can be configured and run completely headless via the
#   command line, which isn't possible with Jenkins.  It should typically be
#   setup to run via cron.
#
#   This script require Git for basic functionality, and Mutt if job results
#   emails are desired.

# TODO Make command line args use getopts
rootBuildPath="${1}"
buildId="${2}"
gitFetchUrl="${3}"
branch="${4}"
cmd="${5}"
emailRecipients="${6}"

buildPath="${rootBuildPath}/${buildId}"
buildPidPath=${buildPath}/pid
gitWorkspacePath="${buildPath}/workspace"
lastCommitPath=${buildPath}/lastCommit
lastJobNumPath=${buildPath}/lastJobNum

# Create the base path for the build if it doesn't already exist.
mkdir -p ${buildPath} || exit 1

# Quit if a PID file exists and the process is still running.
if [ -f "${buildPidPath}" ]; then
    oldPid=$(cat ${buildPidPath})
    ps -p ${oldPid} >/dev/null 2>&1
    if [ "$?" -eq 0 ]; then
        >&2 echo "Build is already running at PID ${oldPid}!"
        exit 1
    fi
fi

# Store our PID for future invocations of this script to find.
echo $$ > ${buildPidPath}
if [ "$?" -ne 0 ]; then
    >&2 echo "Could not create \"${buildPidPath}\"!"
    exit 1
fi

# Grab the SHA1 of the top-most commit the last time this script ran.
oldLastCommit="$(cat ${lastCommitPath})"

# Go into our working repo copy and grab the latest code, or clone it if it
# doesn't exist yet.
if [ -d "${gitWorkspacePath}" ]; then
    cd ${gitWorkspacePath} || exit 1
    git remote remove origin
    git remote add origin ${gitFetchUrl}
    git fetch
else
    git clone ${gitFetchUrl} ${gitWorkspacePath}
    cd ${gitWorkspacePath} || exit 1
fi
git checkout ${branch}
git reset --hard origin/${branch}

# Grab the SHA1 of the top-most commit from the updated repo.
lastCommit="$(git rev-parse ${branch})"

# If the SHA1 hasn't changed, there's nothing to do.
if [ "${oldLastCommit}" == "${lastCommit}" ]; then
    echo "No changes found in branch \"${branch}\""
    exit 0
fi

# Update our stored lastJobNum before doing the build, because we want to
# increment it regardless of the result.
jobNum="$(cat ${lastJobNumPath})"
if [ "$?" == 0 ]; then
    ((jobNum+=1))
else
    jobNum=1
fi
echo ${jobNum} >${lastJobNumPath}

# Create a place to store the meta and results for this job, and update
# the 'latest' symlink.
jobPath=${buildPath}/jobs/${jobNum}
mkdir -p ${jobPath} || exit 1
latestJobLinkPath=${buildPath}/jobs/latest
rm -f ${latestJobLinkPath}
ln -s ${jobNum} ${latestJobLinkPath} || exit 1

# Dump the Git log of the commits we're about to build.
if [ -z "${oldLastCommit}" ]; then
    gitRevRange="${lastCommit}^..${lastCommit}"
else
    gitRevRange="${oldLastCommit}..${lastCommit}"
fi
git log --stat ${gitRevRange} 2>&1 > ${jobPath}/git.log

# Do the build!
echo "Building ${lastCommit} from branch \"${branch}\" in job ${jobNum}"
${cmd} >${jobPath}/build.log 2>&1
jobResult="$?"

# Display results summary and send mail if recipients specified by caller.
summaryMsgPrefix="${buildId} auto build job ${jobNum}"
if [ "${jobResult}" == 0 ]; then
    summaryMsg="${summaryMsgPrefix} succeeded!"
    echo ${summaryMsg}

    if [ -n "${emailRecipients}" ]; then
        head -n 64 ${jobPath}/git.log | mutt -s "${summaryMsg}" \
                -a ${jobPath}/git.log -a ${jobPath}/build.log -- ${emailRecipients}
    fi
else
    summaryMsg="${summaryMsgPrefix} failed!"
    >&2 echo ${summaryMsg}

    if [ -n "${emailRecipients}" ]; then
        tail -n 64 ${jobPath}/build.log | mutt -s "${summaryMsg}" \
              -a ${jobPath}/git.log -a ${jobPath}/build.log -- ${emailRecipients}
    fi
fi

# Update our stored lastCommit last, because we only want to change it when
# this script terminates normally.  This allows it to run again when it
# terminates abnormally.
echo ${lastCommit} >${lastCommitPath}

# Clean up our PID file so that the next invocation of this script will run.
rm -f ${buildPidPath}