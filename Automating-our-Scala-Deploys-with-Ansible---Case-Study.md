Automating our Scala Deploys with Ansible - Case Study
======================================================

<sub>Originally posted to [code.hootsuite.com](http://code.hootsuite.com/?p=284)</sub>
<sub>Written by: Garrett Eidsvig on April 9, 2013</sub>


In my last [post](http://code.hootsuite.com/?p=209) I touched on why we started using [Ansible](http://ansible.cc). I will now try to show how all of our [Scala](http://www.scala-lang.org) project conventions and tools ([SBT](http://www.scala-sbt.org/), Ansible, [Jenkins](http://jenkins-ci.org), Debian package) work together to make automation possible. 



# The Scala Project

The example project that I'm going to be using is, [DistBones](https://github.com/geidsvig/DistBones). This is a bare bones Scala project that is configured to use [Akka](http://akka.io) and the microkernel distribution build type. The service doesn't do anything special, it merely starts up, prints a statement, then shuts down. It does, however, provide a minimal example for building a project using SBT and bundling the result up in a Debian package.

The conventions outlined in the last post indicate that we will need to provide a product and project name. From here on out we'll be using the `geidsvig` for the product name, and `distbones` for the project name.

Let's take a look at the Build.scala file first. For the most part we've got a standard Scala-SBT setup. The only configuration piece that must fit our conventions is the output Dist file, `target/distbones-dist`. Notice that we're using our project name in this value.
```
lazy val DistBonesKernel = Project(
    id = "distbones-kernel",
    base = file("."),
    settings = defaultSettings ++ AkkaKernelPlugin.distSettings ++ Seq(
      libraryDependencies ++= Dependencies.distBonesKernel,
      distJvmOptions in Dist := "-Xms2G -Xmx4G -Xss1M -XX:+UseParallelGC -XX:GCTimeRatio=19",
      outputDirectory in Dist := file("target/distbones-dist")
    )
  )

```
There are also some Akka dependencies, most importantly the microkernel package.
```
val akkaKernel = "com.typesafe.akka" % "akka-kernel" % V.Akka
```


The Debian packaging instructions also reside in our project in the `deb` directory. We found that our packaging varied enough between one project and the next to warrant having this setup. The `make-deb.sh` script takes a SBT dist result and packages it up, using the product and project values. These match our afformentioned `geidsvig` and `distbones` values. You will see how our conventions really start to matter here.
```
rm -rf deb/usr
mkdir -p deb/usr/local/$PRODUCT
cp -R target/$PROJECT-dist deb/usr/local/$PRODUCT/$PROJECT
cp -R conf deb/usr/local/$PRODUCT/$PROJECT/conf
```
We have also added a little Jenkins hook to append the build number to the Scala project version.
```
# Creates version off of project Version and Jenkins build number
version=$(awk '/val/ {if ($2 == "Version") print $4}' project/Build.scala | sed -e 's/\"//g').$BUILD_NUMBER
sed -e 's/Version:/Version\: '"$version"'/g' <deb/DEBIAN/proto-control >deb/DEBIAN/control
```

Of the four example files in the `deb` directory, `prerm` is the only interesting one. Its task is to wipe out a previously installed version of our debian package. The same product and project values show up again in here.
```
#!/bin/bash
cd /usr/local/geidsvig
rm -rf distbones
```

So far our project and make Debian package scripts are nicely contained within DistBones, and can be easily used to perform manual builds and deployment. What we need to do now, is configure our Ansible Playbooks project to handle automation tasks for us.

# Ansible Playbooks

In the example project, [Ansible Playbooks](https://github.com/geidsvig/AnsiblePlaybooks), we have a number of generic scripts and templates that will be used to automate our server provisioning, project deployment and configuration, and service control mechanisms.

If we take a look at the structure of this project, we can see that there are a number of directories. The generic directories that will be shared across all projects using Ansible Playbooks are:

- `inventories`
- `jenkins`
- `plays`
- `templates`

The final directory, `geidsvig`, matches our convention for a unique folder per product.

Within `inventories` we split up our configuration by environments: `dev`, `staging`, and `production`. Our example is overly simplified, so the only differences between each configuration file is the hostname of our `distbones` project, and the environment `env` variable. Below is the `dev` environment configuration.
```
[distbones]
distbones.dev.server.host.com

[distbones:vars]
project_version=1.0

[distparent:children]
distbones

[distparent:vars]
env=dev
```

The single hostname of `distbones.dev.server.host.com` tells Ansible to target this server for all of its actions. In a distributed environment, we will have multiple hosts listed under the `distbones` project header, and each host will have the same actions applied to it.

The project specific `vars` block is a great place to add Scala configuration overrides. These vars are applied to the templates that we will be looking at shortly. The parent group in this example shows how multiple projects can share variables. You may find that with many more projects to maintain, the parent groups reduce a lot of duplicate variable definitions.


The `plays` directory contains all Ansible tasks. These plays are called by the project specific playbook. Each of these tasks is written to be as granular as possible, where the name of the play file should indicate its usage. The tools play is an exception to that rule, in that we always want the tools defined within it to be applied to our clean slate server instance.

In order to push our Debian artifact to our target host we have a `deploy-artifact.yaml` file. At the top are two validation checks to ensure we have our project version and build number. Next up are two ways to transfer our artifacts, one for dev, and the other for staging and production. We've done this, as our server groups are segregated for security purposes. Later when we look at the Jenkins implementation, we will see how our artifacts are archived to these locations. Note that the urls and credentials provided here are examples, and will need to be updated to match a real environment setup.
```
- name: deploy artifact $product-$project-$project_version.$build_number.deb to $env
  get_url: url=http://jenkins.serverhost.com/artifacts/$product/$project/dev/$product-$project-$project_version.$build_number.deb dest=/var/tmp/$product-$project-$project_version.$build_number.deb
  only_if: "'$env' == 'dev'"

- name: deploy artifact $product-$project-$project_version.$build_number.deb to $env
  action: command wget --quiet --no-check-certificate --user=authorized_user --password=valid_pwd https://name.remotehost.com/artifacts/$product/$project/$env/$product-$project-$project_version.$build_number.deb chdir=/var/tmp creates=/var/tmp/$product-$project-$project_version.$build_number.deb
  only_if: "'$env' == 'stg' or '$env' == 'prod'"
```

The tail end of this file installs our Debian package and cleans up the temporary install file.
```
- name: dpkg install $product-$project-$project_version.$build_number.deb
  action: command dpkg -iE /var/tmp/$product-$project-$project_version.$build_number.deb 

- name: clean up /var/tmp/
  action: command rm /var/tmp/$product-$project-$project_version.$build_number.deb
```

Taking a look at the `configure.yaml` file, we see that our two actions consist of making sure the product directory exists at our desired target location, and running a template action to create the configuration file to be applied against our project at run time.
```
- name: ensure directory exists
  action: command mkdir -p /etc/$product

- name: generate config from template
  action: template src=../$product/templates/$project.conf dest=/etc/$product/$project.conf owner=root group=root mode=0644
```

The `initd.yaml` script also contains a template action. This will create the control script on the target host so that we can start|stop|restart our service.
```
- name: generate init.d from template
  action: template src=../templates/sbt-dist-initd.j2 dest=/etc/init.d/$product-$project owner=root group=root mode=0755
```

Moving on to the `templates` directory, we have our solitary `sbt-dist-initd.j2` template. For this script to be useful on our target host, we require a few variables passed into it by Ansible.
```
PRODUCT={{ product }}
SERVICE={{ project }}
JAVA_BOOT_CLASS={{ bootclass.stdout }}
```
The above variables continue our convention of using `product` and `project`. We now introduce a `bootclass` variable. This one looks different from the others because I'm using a bit of a workaround to allow definition of variables during playbook execution. I do this because we have a few projects that have multiple bootclasses and each bootclass will load a different set of instructions and class files. It could be argued that these projects could instead be using a common library, and be split up into their own projects, but that's not concern for us at this time.

We also have an optional variable for JAVA_OPTS, which can be easily overwritten in our inventory files if we need to change anything.
```
JAVA_OPTS={{ java_opts | default("'-Xms512M -Xmx1024M -Xss1M -XX:+UseParallelGC -XX:GCTimeRatio=19'") }}
```

I will not go into detail on the rest of the `sbt-dist-initd.j2` template, as it is fairly well self documented.


The fourth standard directory, `jenkins`, houses the three environment specific scripts for our Jenkins post build configuration. The dev and staging jobs both require the same variables:
```
PRODUCT="$1"
PROJECT="$2"
BUILD_NUMBER="$3"
JENKINS_JOB="$4"
```

Once again, we have `product` and `project` declared at the top. The build number refers to the Jenkins build number, and the Jenkins job variable is the name of the actual Jenkins job as configured in the dashboard. Using these variables we are able to determine our directory paths. The below example is from the dev script.
```
WORKING_DIR="/ebs1/opt/jenkins/jobs/$JENKINS_JOB/workspace"
DOCS_DIR="/var/www/docs/$PRODUCT/$PROJECT/dev"
ARCHIVE_DIR="/ebs1/www/artifacts/$PRODUCT/$PROJECT/dev"
```

The script handles updating the reference.conf file in the Scala project to contain the latest `build.version`. It also copies the README, api docs, and public folder to a common area so that other developers can easily check the latest documentation. We prefer to have our documents reside with our code, because it's one less place to remember to keep up to date.

We then see that the `make-deb.sh` script is called to package our project.
```
function package {
  bash "$WORKING_DIR"/make-deb.sh $BUILD_NUMBER
}
```

Followed by the archival action, and a simple directory clean up.
```
function archive {
  if [ ! -e $ARCHIVE_DIR ]; then
    mkdir -p $ARCHIVE_DIR
  fi
  
  rm -rf $ARCHIVE_DIR/*
  
  mv "$WORKING_DIR"/$PRODUCT-$PROJECT-*.deb $ARCHIVE_DIR/
}
```

Take some time to inspect the staging and production scripts. For the most part they do the same tasks, however they also copy their artifacts to a repository server that the target hosts for those environments have access to. The staging script manages our Git repository tagging for us, a nice little bonus to help with tracking our projects. Also notice how the production script does not contain variables for build number and jenkins job. Instead it requires the version to be passed in. What we've done here is create our Debian artifact in the staging build, and merely reference it and move it around in the production environment script.

Alright, now that we've covered the building blocks that perform all of the tasks, we need to visit how to tie these all together. This is where the playbooks come in. Inside the `geidsvig` directory are a number of these playbooks. We have defined our files to handle specific tasks. These tasks themselves can be chained to great effect.

First up, in the order of how we would use these scripts, we have the `provision-distbones-server.yaml` playbook. This book manages the server dependencies that we want applied to our target host. The variables `product` and `project` are defined as `geidsvig` and `distbones` respectively. Each playbook will provide these parameters, making the creation of new playbooks quite simple.

The second file we would use is the `deploy-distbones-artifact.yaml` file. Beyond defining the hosts name and vars, it does one thing, call the `deploy-artifact.yaml` play.

The third playbook, `configure-distbones-artifact.yaml`, manages the configuration and initd tasks. This file is special in that we need to register the `bootclass` to tell our initd script what class file it needs to execute on. Using the Ansible `register` command is workaround I eluded to earlier with regard to the `sbt-dist-initd.j2` template. In order to extract this value in the template we use the `stdout` function.
```
- include: ../plays/configure.yaml
- name: set bootclass = com.geidsvig.DistBonesBoot
  action: command echo com.geidsvig.DistBonesBoot
  register: bootclass
- include: ../plays/initd.yaml
``` 

The configuration play will use the `geidsvig/templates/distbones.conf`. In the example conf file I have not defined any overrides because our example project, DistBones, doesn't have any configuration.

The fourth and final playbook is `control-distbones-artifact.yaml`. Here we have the automated control script to restart a service upon its deployment. The init.d script created earlier is triggered and we should have a running application if everything up to here is correct.
```
      - name: stop
        action: command /etc/init.d/$product-$project stop
        only_if: "'$cmd' == 'stop' or '$cmd' == 'restart'"

      - name: start
        #action: command /etc/init.d/$product-$project start &
        action: command sh -c "nohup /etc/init.d/$product-$project start 2>&1 >/dev/null &"
        only_if: "'$cmd' == 'start' or '$cmd' == 'restart'"
```

And that does it for our Ansible Playbook project. With these playbooks we can configure any Scala-SBT project using our predefined conventions to be automated. Next up, we will tie it all together using Jenkins.

# Jenkins Configuration

Using Jenkins as our build tool we can create distinct build tasks for each of our environments. We have also created a few generic Ansible jobs to handle server provisioning, reconfiguration, and controlling services, such as commanding a restart. For the following examples to make sense, you need to be aware that our Jenkins home directory is `/ebs1/opt/jenkins` and that we keep our AnsiblePlaybook project up to date with every git checkin. I am also leaving out how we handle authentication for our Jenkins server communicating with our deployment servers.

Our build configuration for server provisioning uses the name `Server Provision`, and is parameterized with 3 Choice param lists:

- inventory: dev, staging, production
- product: ex. geidsvig
- project: ex. distbones

The Build Execution Shell script contains:
```
#!/bin/bash
cd /ebs1/opt/jenkins/jobs/AnsiblePlaybooks/workspace/

ansible-playbook -i inventories/$inventory -v $product/provision-$project-server.yaml
```

The reconfigure build, labeled `Service Reconfigure` also has the inventory, product and project Choice param lists. The Build Execution Shell script contains:
```
#!/bin/bash
cd /ebs1/opt/jenkins/jobs/AnsiblePlaybooks/workspace/

ansible-playbook -i inventories/$inventory -v --extra-vars "version=$project_version" $product/configure-$project-artifact.yaml
```

The control build, titled `Service Control` maintains the same 3 Choices: inventory, product, and project. Its Build Execution Shell has:
```
#!/bin/bash
cd /ebs1/opt/jenkins/jobs/AnsiblePlaybooks/workspace/

ansible-playbook -i inventories/$inventory -v --extra-vars "product=$product project=$project cmd=$action" $product/control-$project-artifact.yaml
```

Our dev environment project build for `DistBones` would have the name `DistBones.MASTER` and be configured to use our git repository and listen for check-ins on the `master` branch. We would set our Build parameters to use the SBT Launcher with actions `clean update compile test doc dist`. Our post build actions would be as follows:
```
cd /ebs1/opt/jenkins/jobs/AnsiblePlaybooks/workspace/
./jenkins/post-build-script.sh geidsvig distbones $BUILD_NUMBER "$JOB_NAME"

ansible-playbook -i inventories/dev -v --extra-vars "build_number=$BUILD_NUMBER" geidsvig/deploy-distbones-artifact.yaml
ansible-playbook -i inventories/dev -v geidsvig/configure-distbones-artifact.yaml
ansible-playbook -i inventories/dev -v --extra-vars "cmd=restart" geidsvig/control-distbones-artifact.yaml
```

The Jenkins staging environment build is pretty much the same. We would call the build `DistBones.STAGING_RELEASE`, and the main difference between this build and the dev build is that we now configure to listen to the `release` branch. The post deploy script would read as follows:
```
cd /ebs1/opt/jenkins/jobs/AnsiblePlaybooks/workspace/
./jenkins/staging-post-build-script.sh geidsvig distbones $BUILD_NUMBER "$JOB_NAME"

ansible-playbook -i inventories/staging -v --extra-vars "build_number=$BUILD_NUMBER" geidsvig/deploy-distbones-artifact.yaml
ansible-playbook -i inventories/staging -v geidsvig/configure-distbones-artifact.yaml
ansible-playbook -i inventories/staging -v --extra-vars "cmd=restart" geidsvig/control-distbones-artifact.yaml
```

Finally, let's take a look at the production build. Sticking with the naming convention, `DistBones.PRODUCTION_RELEASE` is what we'll call it. The parameters for this build differ from the last ones. We will be using:

- joburl : a run parameter that uses the `DistBones.STAGING_RELEASE` job
- servergroup : the ansible host group. ex. distbones

This build is not hooked into git commits. Instead it requires a manual start of the job to select the staging build number to be deployed.
The post Build Execution Shell script will contain:
```
#!/bin/bash
cd /ebs1/opt/jenkins/jobs/AnsiblePlaybooks/workspace/
IFS='/' read -ra joburlarray <<< "$joburl"
buildversion=${joburlarray[5]}

./jenkins/production-post-build-script.sh geidsvig distbones $buildversion

ansible-playbook -i inventories/production -v --extra-vars "build_number=$buildversion" geidsvig/deploy-distbones-artifact.yaml
ansible-playbook -i inventories/production -v geidsvig/configure-distbones-artifact.yaml
ansible-playbook -i inventories/production -v --extra-vars "cmd=restart" geidsvig/control-distbones-artifact.yaml
```

We have also configured rollback jobs. The only difference between a production release and a rollback is to remove the line for `production-post-build-script.sh`.



# In Conclusion

This may look like a lot of work, and it was when I first started down this path. Applying these principles to a project is now quick and painless. We can take a project and upgrade it to full automation in less than an hour. Very much worth our initial investment considering how frequently we deploy our services.



### Reference Github Projects

- [DistBones](https://github.com/geidsvig/DistBones) - A skeleton scala/sbt dist project.
- [AnsiblePlaybooks](https://github.com/geidsvig/AnsiblePlaybooks) - A sample Ansible project to manage multiple scala/sbt projects.

