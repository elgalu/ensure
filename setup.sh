#!/usr/bin/env bash
#
# elgalu/ensure setup/bootstrap script
#   Script to idempotently validate that Python, PyEnv, Poetry, PyInvoke, venv,
#   Git, Docker, ssh-client, etc are installed on Linux and OSX
#
# Can be run with: `curl -sL git.io/elgalu | bash`
#
# This script is idempotent, it will not re-install things but only make sure nothing is missing.
# If you want to force this script to install most things again run `rm -rf ~/.pyenv .venv/`
#
# Tested on:
# - Linux: Ubuntu 20.04.2 LTS
# - OSX..: TODO
#
# :source: https://github.com/elgalu/ensure
# :copyright: (c) 2021 by Leo Gallucci.
# :license: MIT

# set -e: exit asap if a command exits with a non-zero status
set -e

# set -o pipefail: Don't mask errors from a command piped into another command
set -o pipefail

# set -x: prints all lines before running debug (debugging)
[ -n "${DEBUG}" ] && set -x
[ -n "${PYENV_DEBUG}" ] && set -x

#-------------------------#
#--- Program Variables ---#
#-------------------------#
[ -z "$PYENV_ROOT" ] && export PYENV_ROOT="${HOME}/.pyenv"
GITHUB="https://github.com"

# set -u: treat unset variables as an error and exit immediately
set -u

#------------------------#
#--- Helper Functions ---#
#------------------------#
## Output to standard error
function util.log.error() {
    printf "ERROR $(${_date} "+%H:%M:%S:%N") %s\n" "$*" >&2;
}

## Output a warning to standard output
function util.log.warn() {
    printf "WARN $(${_date} "+%H:%M:%S:%N") %s\n" "$*" >&2;
}

## Output an info standard output
function util.log.info() {
    printf "INFO $(${_date} "+%H:%M:%S:%N") %s\n" "$*" >&1;
}

## Output a new line break to stdout
function util.log.newline() {
    printf "\n" >&1;
}

## Print an error and exit, failing
function util.die() {
    util.log.error "$1"
    # if $2 is defined AND NOT EMPTY, use $2; otherwise, set the exit code to: 150
    errnum=${2-150}
    exit "${errnum}"
}

#----------------------------#
#--- OSX vs Linux tooling ---#
#----------------------------#
if [ "$(uname)" == 'Darwin' ]; then
    export _tee='gtee'
    export _cut='gcut'
    export _sed='gsed'
    export _tail='gtail'
    export _date='gdate'
    export _timeout='gtimeout'
elif [ "$(uname)" == 'Linux' ]; then
    export _tee='tee'
    export _cut='cut'
    export _sed='sed'
    export _tail='tail'
    export _date='date'
    export _timeout='timeout'
else
    util.die "Unsupported operating system: $(uname)"
fi

#-----------#
#--- Git ---#
#-----------#
## Git clone each pyenv dependency repo.
function checkout() {
    [ -d "$2" ] || git clone --depth 1 "$1" "$2" || util.die "Failed to git clone $1"
}

## Ensure git client is installed.
function ensure_git() {
    if ! command -v git 1>/dev/null 2>&1; then
        util.die "Git is not installed, can't continue. git command not found in path"
    fi
}

ensure_git

#----------------------#
#--- Git Submodules ---#
#----------------------#
## Ensure git client is installed.
function ensure_git_submodules() {
    if [ -f ".gitmodules" ]; then
        git submodule update --init
    fi
}

ensure_git_submodules

#--------------#
#--- Docker ---#
#--------------#
## Ensure docker client is installed and that doesn't require sudo.
function ensure_docker() {
    if ! command -v docker --version 1>/dev/null; then
        util.log.error "it seems docker is not installed, please install it first."
        docker --version
    fi

    if ! command -v docker ps --last=1 1>/dev/null; then
        util.log.error "it seems docker is installed but it requires sudo, fix that first."
        docker ps --last=1
    fi
}

ensure_docker

#------------------------------------#
#--- SSH client and other tooling ---#
#------------------------------------#
## Ensure ssh client is installed.
function ensure_ssh_client() {
    if ! command which ssh 1>/dev/null; then
        util.die "it seems ssh is not installed, please install a tool like openssh-client."
    fi
    if ! command which ssh-keygen 1>/dev/null; then
        util.die "it seems ssh-keygen is not installed, please install a tool like openssh-client."
    fi
    if ! command which ssh-copy-id 1>/dev/null; then
        util.die "it seems ssh-copy-id is not installed, please install a tool like openssh-client."
    fi
    if ! command which sftp 1>/dev/null; then
        util.die "it seems sftp is not installed."
    fi
}

ensure_ssh_client

#-------------------------------------#
#--- Ensure we have grep, awk, etc ---#
#-------------------------------------#
function ensure_system_helpers() {
    if ! command grep --version 1>/dev/null; then
        util.die "it seems grep is not installed, please install it."
    fi
    if ! command awk --version 1>/dev/null; then
        util.die "it seems awk is not installed, please install it."
    fi
}

ensure_system_helpers

#-----------------------------#
#--- Ensure Python version ---#
#-----------------------------#
## Installs PyEnv in current user's home, rootless.
function install_pyenv() {
    checkout "${GITHUB}/pyenv/pyenv.git"            "${PYENV_ROOT}"
    checkout "${GITHUB}/pyenv/pyenv-doctor.git"     "${PYENV_ROOT}/plugins/pyenv-doctor"
    checkout "${GITHUB}/pyenv/pyenv-installer.git"  "${PYENV_ROOT}/plugins/pyenv-installer"
    checkout "${GITHUB}/pyenv/pyenv-update.git"     "${PYENV_ROOT}/plugins/pyenv-update"
    checkout "${GITHUB}/pyenv/pyenv-virtualenv.git" "${PYENV_ROOT}/plugins/pyenv-virtualenv"
    checkout "${GITHUB}/pyenv/pyenv-which-ext.git"  "${PYENV_ROOT}/plugins/pyenv-which-ext"
}

## Validates PyEnv is working
# https://github.com/pyenv/pyenv
function validate_pyenv() {
    if ! command -v pyenv 1>/dev/null; then
        util.log.error "it seems you still have not added 'pyenv' to the load path."

        { # Without args, `init` commands print installation help
            "${PYENV_ROOT}/bin/pyenv" init || true
            "${PYENV_ROOT}/bin/pyenv" virtualenv-init || true
        } >&2

        if eval "$("${PYENV_ROOT}"/bin/pyenv init -)"; then
            util.log.info "PyEnv initialized"
        else
            util.die "PyEnv failed to initialize with init -"
        fi
    fi
}

function pyenv_ensure_required_python_version() {
    if [ ! -f ".python-version" ]; then
        util.die "Please create a file named .python-version before proceeding."
    fi
    _required_python_version=$(cat .python-version)
    if ! pyenv install "${_required_python_version}" --skip-existing; then
        util.die "Failed to pyenv_ensure_required_python_version"
    fi
}

## https://github.com/pyenv/pyenv
function ensure_python_version() {
    # Checks for `.pyenv` file, and suggests to remove it for installing
    if [ -d "${PYENV_ROOT}" ]; then
        util.log.info "PyEnv seems to be installed already at '${PYENV_ROOT}'."
        validate_pyenv
        pyenv_ensure_required_python_version
    elif [ "${USER}" == "root" ]; then
        util.log.info "We're running as root, will skip installing PyEnv."
        if python --version | grep "$(cat .python-version)"; then
            util.log.info "We're already running the required version of Python."
        else
            util.log.error "We'll not install PyEnv while running as root, please ensure you have a matching Python version according to .python-version file."
            cat .python-version
            python --version
            exit 10
        fi
    else
        install_pyenv
        validate_pyenv
        pyenv_ensure_required_python_version
    fi
}

# Just in case, deactivate any active environments
deactivate nondestructive 1>/dev/null 2>&1 || true
deactivate nondestructive 1>/dev/null 2>&1 || true
deactivate nondestructive 1>/dev/null 2>&1 || true

if ! ensure_python_version; then
    util.die "Failed to ensure_python_version"
fi

#----------------------------------#
#--- Ensure Virtual Environment ---#
#----------------------------------#
## https://docs.python.org/3/library/venv.html
function ensure_venv() {
    if [ ! -d ".venv" ]; then
        if ! python -m venv .venv; then
            util.die "Failed create .venv"
        fi
        if ! .venv/bin/python -m pip install --upgrade pip; then
            util.die "Failed upgrade pip"
        fi
    fi
}

ensure_venv

source ".venv/bin/activate" || util.die "Failed to activate the virtual environment"

#---------------------#
#--- Ensure Poetry ---#
#---------------------#
## https://github.com/python-poetry/poetry
function ensure_poetry() {
    # Do not install poetry within your virtual environment
    if command -v poetry --version 1>/dev/null; then
        poetry self update || util.die "Failed to self update poetry."
    else
        util.log.error "Please install poetry yourself, outside this project's environment, e.g."
        util.log.error "curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/install-poetry.py | python -"
        exit 20
    fi
    # --no-root: Do not install the root package (your project).
    if ! poetry install --no-root; then
        util.die "Failed to poetry install all required dependencies"
    fi
}

ensure_poetry

#-----------------------#
#--- Ensure PyInvoke ---#
#-----------------------#
## https://github.com/pyinvoke/invoke
function ensure_pyinvoke_if_needed() {
    if [ -f "tasks.py" ] || [ -f "invoke.yaml" ]; then
        # let's make sure `poetry run` and `invoke` work
        if ! poetry run invoke setup; then
            util.die "Failed to poetry run invoke setup"
        fi
        # let's make sure we don't need `poetry run` since the .venv is activated anyways
        if ! invoke tests; then
            util.die "Failed to run tests"
        fi
        if ! invoke hooks; then
            util.die "Failed to run hooks"
        fi
    else
        util.log.info "This project doesn't seem to be using pyinvoke."
    fi
}

ensure_pyinvoke_if_needed

#-----------------------------------#
#--- Ensure Ansible Dependencies ---#
#-----------------------------------#
## Ensure Ansible Galaxy roles (dependencies) are downloaded and up to date.
# Ansible Galaxy is the way to share Ansible PlayBooks with the open source community.
function ensure_ansible_if_needed() {
    if [ -f "ansible.cfg" ]; then
        if command -v ansible-galaxy --version 1>/dev/null; then
            util.die "ansible.cfg file found in this project but ansible-galaxy is not installed."
        fi
        if [ -f "*/requirements.yml" ]; then
            util.log.info "Ensure Ansible Galaxy roles (dependencies) are downloaded and up to date..."
            # `ansible-galaxy`: command to manage Ansible roles in shared repositories,
            # the default of which is Ansible Galaxy https://galaxy.ansible.com
            ansible-galaxy collection install --force -r roles/requirements.yml >/dev/null
            ansible-galaxy role install --force -r roles/requirements.yml >/dev/null
            ansible-galaxy collection install --force -i -r config/requirements.yml >/dev/null
            ansible-galaxy role install --force -i -r config/requirements.yml >/dev/null
        fi
    else
        util.log.info "This project doesn't seem to be using Ansible."
    fi
}

ensure_ansible_if_needed

#--------------------------------#
#--- Ensure Dockerfile linter ---#
#--------------------------------#
## https://github.com/hadolint/hadolint
function ensure_hadolint_if_needed() {
    if test -n "$(find . -maxdepth 3 -name 'Dockerfile' -print -quit)"; then
        if command -v hadolint --version 1>/dev/null; then
            util.log.error "Dockerfile(s) found on this project but hadolint is not installed."
            util.log.error "https://github.com/hadolint/hadolint#install"
        fi
    else
        util.log.info "This project doesn't seem to be using Dockerfile(s)."
    fi
}

ensure_hadolint_if_needed

#------------#
#--- DONE ---#
#------------#
util.log.info ""
util.log.info "#----------------------------------------------#"
util.log.info "# SUCCESS! Now activate your environment with: #"
util.log.info "#     source .venv/bin/activate                #"
util.log.info "#----------------------------------------------#"
