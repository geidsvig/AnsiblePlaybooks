Automating our Scala Deploys with Ansible
=========================================

<sub>Originally posted to [code.hootsuite.com](http://code.hootsuite.com/?p=209)</sub>
<sub>Written by: Garrett Eidsvig on April 9, 2013</sub>

Manually provisioning our servers with all of a service's Unix dependencies is time consuming, and repeating the steps on multiple instances can be error prone. Thankfully a number of automation tools exist to handle repeatable jobs for us. One such tool is [Ansible](http://ansible.cc), it's awesome, you should use it!

We took Ansible a few steps beyond server provisioning tasks and started using it in our [Jenkins](http://jenkins-ci.org) builds to auto-deploy to our dev and staging environments. We've even added production one-click deployments to Jenkins using our successful staging release candidates. Manually deploying to servers is now a thing of the past for all of our [Scala](http://www.scala-lang.org) projects.

# The Finer Points

Creating automation tasks can be tricky, so in order to reduce the complexity of our deployment processes and configuration we agreed on a number of conventions:

- All Scala projects are built as [Akka](http://akka.io) microkernels with the `sbt dist` command, and have a make-deb.sh shell script that bundles the distribution into an installable artifact.
- Projects use [Git](http://git-scm.com) and have two main branches: `master` and `release`, where `master` is the trunk, and `release` is merged into to create release candidates.
- Projects have a naming convention with a specific `product` and `project`, even if the two are the same
- Unix servers are configured identical to each other, and deployed services have the same directory structures:
 - service configuration @ `/etc/[product]/[service].conf`
 - logging @ `/var/log/[product]/[service].log`
 - artifact deployed @ `/usr/local/[product]/[service]/*`
 - init.d scripts @ `/etc/init.d/[product]-[service]`
 - optional cron.d jobs @ `/etc/cron.d/[product]-[service]`
- An Ansible project was created to store all playbooks and plays. We split playbooks by projects, and share common plays and templates. We also split up tasks by types:
 - provision plays (install server dependencies)
 - deployment plays (handle git tagging, debian packaging, archiving debian artifact, and deploying artifact)
 - configuration plays (handle project specific configuration)
 - control plays (start/stop/restart service)
 - inventory files (provide environment specific configuration params and target host information)


# Results

Our conversion to automated Jenkins builds running Ansible post deploy tasks has made us a happy group of developers. We no longer have to manage dev and staging deployments, taking time out of our tight development schedules. Code checked into the `master` branch automatically goes out to dev, code merged into `release` gets shipped to staging and tagged. Then when we're satisfied with our staging version we can push the release to production with the click of a button.


### Code Examples

In an attempt to shed some light on how I've gone about combining all of the above, I have created two Git projects. I will follow up with a [case study](http://code.hootsuite.com/?p=284) about how the following examples can be tied together using Jenkins.

- [DistBones](https://github.com/geidsvig/DistBones) - A skeleton scala/sbt dist project.
- [AnsiblePlaybooks](https://github.com/geidsvig/AnsiblePlaybooks) - A sample Ansible project to manage multiple scala/sbt projects.

