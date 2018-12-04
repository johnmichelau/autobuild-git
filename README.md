# git-autobuild
A simple continuous build tool that's entirely command-line configurable.

## Why not just use an existing tool (ex: Jenkins)?
I found myself in a situation where I could not host Jenkins or any other CI/CD tool, but I still wanted the benefits that CI/CD offer.  I had a limited amount of time, so I wrote this simple bash script.  In my case, I was using Gradle for my build, so I was able to trigger things such as static code analysis and automated deployment as Gradle tasks.  This proved to be a suitable replacement for Jenkins plugins and the like.
