# New notes for reusability

- `MODULE_NAME` is the name of the module deployed (e.g. `payu`).
  `MODULE_VERSION` is the version of the module deployed (e.g. `1.2.0`) set to  a variable used.
  So the env/module would be loaded using `MODULE_NAME/MODULE_VERSION` (e.g., `module load payu/1.2.0`)
- `ENV_OVERRIDES_DIR` is set to $REPO_PATH/environments/$MODULE_NAME/overrides.
  The overrides directory can be created within each environment, to add specific overrides to general configuration settings.
  Current overrides files used might be:
  - `overrides/scripts/config.sh`cc
  - `overrides/modules/module_file`
  - `overrides/modules/.modulerc`
- Some hosts directories (for example `/g` and `/scratch`) on Gadi are automatically bound to the container because of Gadi's singularity configuration file.
- The internal Python environment is activated within the container, not when the module is loaded. When the module is loaded, only a few related env variables are set (`CONDA_PREFIX`, `CONDA_PROMPT_MODIFIER`)
- To run in debug mode, re-run workflow enabling debug logging
- All files are environment version specific. There are no common files used across multiple environments or environment versions. This makes each environment version completely stand-alone and not touched by any updates of the "default" infrastructure.
- The _environment type_ (`ENV_TYPE`) can be `STABLE` or `DEVELOPMENT` (prerelease). 
  - DEVELOPMENT envs are used to test the functionality of the development packages within the environment. The dev packages will be those installed using pip + git, for example:
    ```yml
      - pip:
        - git+https://github.com/OWNER/REPO.git@REF
        - git+https://github.com/OWNER2/REPO2.git@REF2
    ```
  - STABLE is used for non-development environments, where all packages are specified with defined versions and installed from Anaconda (preferably) or PyPI.
- The _deployment stage_ (`DEPLOYMENT_STAGE`) can be `STAGING` or `PRODUCTION`.
  PRODUCTION environments live in the folder used by the end users.
  STAGING environments live in a testing folder (usually not advertised to the end user).
  STAGING environments are used for testing and validating the infrastructure (not the specific functionalities of the internal packages), mainly carried out automatically within CI. 
  The _deployment stage_ is independent from the _environment type_.

There can be four independent scenarios in total:
| | **DEVELOPMENT** | **STABLE** |
|---|---|---|
| **STAGING** | Dev environments (git) deployed in the staging folder for infrastructural testing (through CI) | Stable environments (Anaconda/PyPI) deployed in the staging folder for infrastructural testing (through CI) |
| **PRODUCTION** | Dev environments (git) deployed in the production folder to be tested for functionality by some users | Stable environments (Anaconda/PyPI) deployed in the production folder to be used by users in their day-to-day workflows |

The environments are deployed in the following scenarios:
- DEVELOPMENT environments in PRODUCTION can be deployed as a workflow dispatch (for example if a dev package specified in `environment_dev.yml` gets updated) by providing the environment name.
- When a pull request is opened or syncronised against the `main` branch of the repo:
   - If the changes involve the `environments` folder, for each environment subfolder changed:
       - If the changes involve the `environment_dev.yml`, a DEVELOPMENT environment in STAGING is deployed (even if there are also changes to the `environment.yml`)
       - If the changes don't involve the `environment_dev.yml`, a STABLE environment in STAGING is deployed
   - If the changes don't involve the `environments` folder, a `payu` STABLE environment in STAGING is deployed, only for infrastuture automatic testing.
- When a pull request is merged to `main` (PR to main is closed with merge), if the changes involved any `environment_dev.yml` file, a DEVELOPMENT environment in PRODUCTION is deployed for each environment changed.
- STABLE environment in PRODUCTION (the actual environment full release) can be deployed as a workflow dispatch by providing the environment name and version to be deployed.

- The disk and inodes consumption for each each env version depends on the env specification. 
  However, an average environment version should consume around ~1GB and ~500 inodes.

- The `manifest.txt` is a file that keeps tracks of the files and folders created for a specific environment version. This makes deletion of a specific version easy, by running: `xargs rm -vrf < "$MANIFEST_FILE_PATH"`

- Changes that are needed in the host when they load the module should go in the `launcher.sh` script.
  Changes that are needed only within the container should go in the `env_activation.sh` script.

- Each deployment creates an `hpc_target_deployment_info.json` JSON file that contains information about deployments for the specific HPC target. It is used to pass structured information from the HPC deployment to the GitHub runner to be used by later steps.

## Note from CMS wiki
The actual container used as the base of the environment contains only enough components to create a functional environment. The container does not contain its own operating system, instead, it is comprised of a series of empty directories and symlinks. The necessary components of Gadi’s operating systems are bind-mounted in at launch time through the launcher script. Though this does make the environment entirely unportable, which goes against the philosophy of containerisation, the container itself only needs to be constructed once for any given system, and reconstruction is trivial. The advantage of this approach is that the conda environment is separate to the container, and therefore multiple conda environments can be present ‘in’ the same container. This also means that the container can never be out of sync as Gadi’s OS receives updates. This allows us to make modifications to the conda environment after installation that enhance the functionality of the environment.

## Infrastructure
STAGING environments are deployed within the `staging_base_dir` (set within `defaults/scripts/config.sh`).
When a PRODUCTION environment is released, the same deployment script is run, but with base directory set to `STABLE_PRODUCTION_BASE_DIR` instead (set within `defaults/scripts/config.sh`).
This allows the staging directory to have the same exact structure and files as the related production directory, so STAGING modules can be tested before being released in PRODUCTION by running the same `module load ...` commands that would be run for PRODUCTION modules.
The only change would be the `module use ...` command, that would need to be specific to the staging directory (`staging_base_dir`).

We define the `production` GitHub environment to grant an extra level of security for environemnts deployed for production (both `STABLE` or `DEVELOPMENT`).

## Things to add







================================================
================== OLD README ==================
================================================


# Containerised Conda Environments

## Overview

This repository is forked from [CMS Containerised Conda environments](https://github.com/coecms/cms-conda-singularity)
which is an approach to deploying and maintaining large conda environments
while reducing inode usage and increasing performance. It takes advantage of
`singularity`'s ability to manage overlay and SquashFS filesystems.
 Each conda environment is consolidated into its own SquashFS file, and then
 one or more of these SquashFS environments are loaded using components
 of the environment. For more information on the CMS containerised environments,
 see the [Conda hh5 environment setup page on the CMS Wiki](https://coecms.github.io/cms-wiki/resources/resources-conda-setup.html).

The environments in this repository are deployed to NCI on Gadi and can be activated using Environment Modules. To use the released modules, ensure you are a member of the `vk83` project. If not, see [how to join an NCI project](https://access-hive.org.au/getting_started/set_up_nci_account/#join-relevant-nci-projects).

There are currently two environments configured in this repository:

- **`payu`**:

 This a released payu environment with a version matching a tagged version of the [`payu-org/payu`](https://github.com/payu-org/payu) repository. To load this module, run:

```shell
module use /g/data/vk83/modules
module load payu # To load the latest tagged version
# To load a specific version of payu, instead run: module load payu/VERSION, e.g. module load payu/1.1.6
payu --help # Payu commands can now be run
```

- **`payu-dev`**:

 This is the development payu environment that has the latest changes on the `payu-org/payu` repository's `master` branch. To load this module, run:

```shell
module use /g/data/vk83/prerelease/modules # Note the prerelease directory
module load payu/dev # To load the latest built version
```

If you encounter any problems running the above environments, please submit an issue [here](https://github.com/ACCESS-NRI/model-release-condaenv/issues).

Below contains instructions for developers on updating the conda environments and some general notes on how all the scripts and workflows interact.

## Updating the Conda Environments

### Environment Directory Structure

Each conda environment has a subdirectory in `environments/` with the same name as the environment. There should be the following files in each subdirectory `:

- **`environment.yml`**: The conda environment file

- **`config.sh`**:
 This script sets up environment variables required for the build, test, and deploy scripts. It requires at least the following to be set:
  - `FULLENV` - Name of the SquashFS file and script directories related to an environment version, e.g. `payu-1.1.6`
  - `MODULE_VERSION` - By default the module name is `conda` and so if the `MODULE_VERSION` is `payu-1.1.6`, the module can be loaded by `module load conda/payu-1.1.6`. Note that for payu, pre-existing modules were loaded using `module load payu/1.1.6`. To maintain this naming scheme, `MODULE_VERSION` is set to `1.1.6`, and `MODULE_DIR` overrides the default variable in `/scripts/config.sh`.

- **`build_inner.sh`** (optional):
 This script can modify environment files during the build scripts before the environment is compressed into a SquashFS file.

- **`deploy.sh`** (optional):
This script runs at the end of the general deploy script after the environment components have been deployed. It is useful for updating the stable or default alias for a modulefile.

- **`testconfig.yml`**:
 This is a configuration file used in the test scripts. This file specifies Python modules to skip loading, ignore exceptions, and modules to preload before testing.

### Releasing a new `payu` environment

1. Clone this repository and create and checkout a new branch.
2. Modify the payu version in the conda environment file - `environments/payu/environment.yml`. If payu version is not set, it'll use the latest payu version in [`access-nri` conda channel](https://anaconda.org/accessnri/payu).
3. Modify `VERSION_TO_MODIFY` and `STABLE_VERSION` in `environments/payu/config.sh`. `VERSION_TO_MODIFY` builds a payu environment with this version, and `STABLE_VERSION` is used in deployment to set the default version alias for the payu module. In most cases these should be set to the same value.
4. Add any new packages or versions to `environment.yml` required for the next release.
5. Push the changes and open a Pull Request to the `main` branch of this repository `ACCESS-NRI/model-release-condaenv` (not the upstream `coecms/cms-conda-singularity` repository).
6. Once a Pull Request is open, it will request a sign-off to run the Build and Test job on the `Gadi` Github Environment. These jobs are performed in temporary locations on Gadi, and so will not affect the production environments.
7. Once the CI jobs have been completed successfully and the Pull Request has also been approved, the branch can be merged, and then the Deploy job will request to run again on the `Gadi` Github Environment.
8. Once deployed, check loading the new module with:

    ```shell
    module use /g/data/vk83/modules
    module load payu/<VERSION>
    ```

    Where `<VERSION>` is the version installed.

### Updating the `payu-dev` environment

The deploy `payu-dev` Github workflow runs every day to check for new commits to the payu repository's `master` branch. It can also be triggered manually to add updates to packages, or once a Pull Request is merged that modifies the `payu-dev` environment files.

To modify the environment via a Pull Request:

1. Clone this repository and create and checkout a new branch.
2. Add packages or version constraints in the conda environment file `environments/payu-dev/environment.yml`.
3. Unlike when updating the `payu` environment above, make sure to leave `VERSION_TO_MODIFY=dev` in `environments/payu-dev/config.sh` unchanged as a version is generated at the time of deployment to include the date-time, and the latest payu commit (e.g. `dev-20250116T002805Z-20a8e76`).
4. Push the changes and open a Pull Request to the `main` branch of this repository `ACCESS-NRI/model-release-condaenv` (not the upstream `coecms/cms-conda-singularity` repository).
5. Once a Pull Request is open, it will request a sign-off for a Build and Test job that runs on the `Gadi Prerelease` environment.
5. When the Pull Request is merged, a custom `payu-dev` deploy workflow will run which will re-run the build and test scripts with the generated environment version before running the deploy scripts. This is to ensure the environment deployed contains the latest changes from the `payu` repository.
8. Once deployed, check loading the new module with:

    ```shell
    module use /g/data/vk83/prerelease/modules
    module load payu/dev
    ```

    Check the `payu/dev` environment contains the updates specified in the merge pull-request.

## Deployed Conda Environment Components

Given a base install directory defined by `BASE_DIR` (see [Github Environment settings](#github-environment-settings)), the structure of apps and modules deployed would look something like the following for `payu/1.1.6`

```bash
├── apps
│   ├── base_conda
│   │   ├── bin
│   │   │   └── micromamba # Micromamba used to install environments in build scripts
│   │   ├── envs
│   │   │   ├── payu-1.1.6 -> /opt/conda/payu-1.1.6 # Symlink to conda environment path inside the container
│   │   │   ├── payu-1.1.6.sqsh # SquashFS file which contains the conda environment
│   │   └── etc
│   │       └── base.sif # Base singularity image
│   └── conda_scripts 
│       ├── launcher_conf.sh
│       ├── launcher.sh
│       ├── overrides
│       └── payu-1.1.6.d # Launcher scripts for the environment
│           ├── bin
│           │   ├── payu -> launcher.sh
│           │   ├── python3 -> launcher.sh
│           │   ├── # Launcher script symlinks for every entry point in the conda environment
│           │   ├── launcher_conf.sh
│           │   ├── launcher.sh # Runs commands inside the containerised environment
│           └── overrides
│  
└── modules
    └── payu
        ├──.common_v3 # The common Environment Modulefile
        ├──.1.1.6 # Custom module insert
        └──1.1.6 -> .common_v3
```

Running `module load payu/1.1.6` adds the launcher scripts in `apps/conda_scripts/payu-1.1.6.d/bin` to the `$PATH`. It also sets up environment variables as if `micromamba activate` was run on the micromamba environment. `SINGULARITYENV_PREPEND_PATH` is set to `/opt/conda/payu-1.1.6/bin` which modifies `$PATH` only inside a singularity container.

If outside the container, running `payu setup` command calls the launcher script (e.g. `apps/conda_scripts/payu-1.1.6.d/bin/payu`), which runs a `singularity exec` command that uses the base container in `apps/base_conda/etc/base.sif` and adds the overlay of the SquashFS file `apps/base_conda/envs/payu-1.1.6.sqsh`. The SquashFS is a read-only file system that is mounted to the base container at runtime. This means all the files in `/opt/conda/payu-1.1.6` are now accessible inside the container. The launcher script then runs `payu setup` command inside the container, (e.g. `/opt/conda/payu-1.1.6/bin/payu`).

If the `payu setup` launcher script is invoked inside the container, it will instead run the `payu setup` command directly.

## Github Workflows Overview

General overview of the bash scripts used in the Github workflows:

- **Build script** (`scripts/build.sh`)
  - Launches the base singularity container and mounts `/g` directory to a temporary directory on `/jobfs` so it does not affect the production environments but inside the container, it is as-if building directly to the deployed locations. Then:
    - installs a base micromamba, if it doesn't already exist.
    - builds the micromamba environment
    - creates all the launcher scripts
    - sets up the modulefiles
    - runs any custom environment `build_inner.sh` scripts
  - Creates a SquashFS file of the environment and stages this file (in `$ADMIN_DIR/staging`).
  - Once the build is done, archives the environment components into a tar file and stages this file.

- **Test Script** (`scripts/test.sh`)
  - Unpacks the archived tar file of the built environment components to a temporary location.
  - Launches the container with the built SquashFS overlay.
  - Inside the container, run pytests that attempt to import all accessible Python modules. This uses settings defined in an environment's `testconfig.yml` file.

- **Deploy Script** (`scripts/deploy.sh`)
  - Unpacks the archived tar file of the built environment components to a temporary location.
  - Rsyncs the apps and modules directories, and moves the SquashFS file to the deployed locations.
  - Stores the archived tar file in the admin directory.
  - Runs any custom environment `deploy.sh` scripts.

### Pull Request Workflow (`pull_request.yml`)

On a Pull Request to the `main` branch of this repository, it will check for changes to any conda environment configuration files (under `environments/`). If changes are detected, it will build a base singularity container on a Github runner, and request a signoff to deployment to a Github Environment. Once approved, it will rsync the repository and the built base container to Gadi, then run the build and test scripts which are submitted as PBS jobs.

### Deploy Workflow (`deploy_conda.yml`)

Once a Pull Request is merged, it will request a sign-off to deploy to a Github Environment. Once approved, it will run the deploy script on a login node. This workflow does not run for the `payu-dev` environment which is instead deployed by the below workflow.

### Custom Payu-Dev Deploy Workflow (`deploy_payu_dev.yml`)

This workflow runs:

- when there's a merged Pull Request that modifies any `payu-dev` environment files
- if there have been recent commits to [`payu-org/payu` repository's](https://github.com/payu-org/payu) `master` branch. This runs on a cron every morning.
- if the workflow has been triggered manually

It will build a base singularity container on a Github runner. Then it will generate the version for the environment with the format `dev-$DATETIME-$GIT_COMMIT_HASH`, and modify the versions in the `payu-dev` environment files. It will then request signoff to the `Gadi Prerelease` environment. Once approved, it will rsync the repository with the modified environment files down to Gadi. It will re-run the build and test scripts so the built files use the generated dev version. It'll then deploy all required files to the Prerelease location on Gadi. It'll set `payu/dev` module alias to point to the deployed module version. Finally, it'll delete all old versions of `payu/dev-*` environment components, except the recently deployed version, and the previous `payu/dev` version which could be being actively used at the time of the deployment.

### Deploy Payu telemetry configuration (`deploy_telemetry_config.yml`)

This workflow runs either on a manual trigger or when the `telemetry/payu` files have been modified. It creates and substitutes the payu telemetry configuration saved to the Github Environment into a file and deploys it to a location on Gadi.

## Github Configuration

There are currently two Github Environments for deployment: `Gadi` and `Gadi Prerelease`. Any build, test, and/or deploy workflows that need to run on Gadi, currently require a sign-off.

Repository settings:

- `vars.PRERELEASE_ENVIRONMENTS`: Space-separate list of quoted environments to deploy to `Gadi Prerelease`, (e.g. `"payu-dev"`)

### Github Environment settings

Secrets required for SSH:

- `secrets.HOST`: Hostname for the environment
- `secrets.HOST_DATA`: Hostname for the data mover
- `secrets.SSH_USER`: Username for the account used for deployment
- `secrets.SSH_KEY`: Private SSH key for the user

Variables required for Build/Test/Deploy workflows:

- `vars.BASE_DIR` - Base deployment directory that contains `apps/` and `modules/` subdirectories (e.g for `Gadi`: `/g/data/vk83` and for `Gadi Prerelease`: `/g/data/vk83/prerelease/`). **Note:** Currently, the build scripts expect `BASE_DIR` directory to be in `/g/data`.
- `vars.ADMIN_DIR`: Directory to store staging and log files, and tar files of deployed conda environments (e.g. `/g/data/vk83/admin/conda_containers/prerelease`)
- `vars.GROUP_OWNER`: Permissions of read and execute for files installed to apps and modules (e.g. `vk83`)
- `vars.OWNER`: User with read, write, and execute permissions for installed files
- `vars.PROJECT`: Project code used for build and test PBS jobs (e.g. `tm70`)
- `vars.STORAGE`: Storage directives for build and test PBS jobs (e.g. `gdata/vk83`)
- `secrets.PAYU_TELEMETRY_CONFIG`: Sets environment variable for the Payu telemetry configuration path which is passed to the launcher script configuration. This means this environment variable is set every time the container runs.

Additional variables required for Payu telemetry configuration workflow:

- `secrets.PAYU_TELEMETRY_URL`: URL used for Payu telemetry requests. This will point towards the ACCESS-NRI services payu telemetry endpoint.
- `secrets.PAYU_TELEMETRY_TOKEN`: Token for the Payu telemetry requests.
- `vars.PAYU_TELEMETRY_PROXY_URL`: URL used to route telemetry requests via the persistent session proxy.
- `vars.PAYU_TELEMETRY_SERVICE_NAME`: Name of the Payu service in ACCESS-NRI tracking services.
- `vars.HOSTNAME`: Name of HPC environment to add to telemetry information.
