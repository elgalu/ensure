#!/usr/bin/env bash
#
# setup/bootstrap script
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

#------------------------#
#--- Helper Functions ---#
#------------------------#
## Output to standard error
function util.log.error() {
    printf "ERROR $(${_date} "+%H:%M:%S:%N") %s\n" "$*" >&2
}

## Output a warning to standard output
function util.log.warn() {
    printf "WARN $(${_date} "+%H:%M:%S:%N") %s\n" "$*" >&2
}

## Output an info standard output
function util.log.info() {
    printf "INFO $(${_date} "+%H:%M:%S:%N") %s\n" "$*" >&1
}

## Output a new line break to stdout
function util.log.newline() {
    printf "\n" >&1
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
    if ! command -v gdate 1>/dev/null 2>&1; then
        util.die "GNU date is not installed, run: brew install coreutils"
    fi
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
    if ! command -v docker --version 1>/dev/null 2>&1; then
        util.log.error "it seems docker is not installed, please install it first."
        docker --version
    fi

    if ! command -v docker ps --last=1 1>/dev/null 2>&1; then
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
    if ! command which ssh 1>/dev/null 2>&1; then
        util.die "it seems ssh is not installed, please install a tool like openssh-client."
    fi
    if ! command which ssh-keygen 1>/dev/null 2>&1; then
        util.die "it seems ssh-keygen is not installed, please install a tool like openssh-client."
    fi
    if ! command which ssh-copy-id 1>/dev/null 2>&1; then
        util.die "it seems ssh-copy-id is not installed, please install a tool like openssh-client."
    fi
    if ! command which sftp 1>/dev/null 2>&1; then
        util.die "it seems sftp is not installed."
    fi
}

ensure_ssh_client

#-------------------------------------#
#--- Ensure we have grep, awk, etc ---#
#-------------------------------------#
function ensure_system_helpers() {
    if ! command grep --version 1>/dev/null 2>&1; then
        util.die "it seems grep is not installed, please install it."
    fi
    if ! command mawk -W version 1>/dev/null 2>&1; then
        util.die "it seems mawk is not installed, please install it, e.g. brew install mawk"
    fi
}

ensure_system_helpers

#-----------------------------#
#--- Ensure Python version ---#
#-----------------------------#
## Installs PyEnv in current user's home, rootless.
function install_pyenv() {
    util.log.info "Installing PyEnv..."
    checkout "${GITHUB}/pyenv/pyenv.git" "${PYENV_ROOT}"
    checkout "${GITHUB}/pyenv/pyenv-doctor.git" "${PYENV_ROOT}/plugins/pyenv-doctor"
    checkout "${GITHUB}/pyenv/pyenv-installer.git" "${PYENV_ROOT}/plugins/pyenv-installer"
    checkout "${GITHUB}/pyenv/pyenv-update.git" "${PYENV_ROOT}/plugins/pyenv-update"
    checkout "${GITHUB}/pyenv/pyenv-virtualenv.git" "${PYENV_ROOT}/plugins/pyenv-virtualenv"
    checkout "${GITHUB}/pyenv/pyenv-which-ext.git" "${PYENV_ROOT}/plugins/pyenv-which-ext"
}

## Validates PyEnv is working
# https://github.com/pyenv/pyenv
function validate_pyenv() {
    if ! command -v pyenv 1>/dev/null 2>&1; then
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
    elif [ "${USER}" == "root" ] || [ "${USER}" == "" ]; then
        util.log.info "We're running as root, will skip installing PyEnv."
        if python --version | grep "$(cat .python-version)"; then
            util.log.info "We're already running the required version of Python."
        else
            util.log.error "We'll not install PyEnv while running as root."
            util.log.error "Please ensure you have a matching Python version according to .python-version file."
            cat .python-version
            util.log.error "Current Python version:"
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
    if command -v poetry --version 1>/dev/null 2>&1; then
        if [ -z "${CDP_BUILD_VERSION}" ]; then
            poetry self update || util.die "Failed to self update poetry. Quitting..."
        else
            util.log.info "Running in CDP, will not upgrade poetry."
        fi
    else
        util.log.error "Please install poetry yourself, outside this project's environment, e.g."
        util.log.error "curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py | python -"
        exit 20
    fi
    # --no-root: Do not install the root package (your project).
    if ! poetry install --no-root; then
        util.die "Failed to poetry install all required dependencies"
    fi
}

ensure_poetry

#-------------------------#
#--- Ensure GitHub/Hub ---#
#-------------------------#
## https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian-ubuntu-linux-apt
function ensure_github_cli_releases() {
    if ! command -v gh --version 1>/dev/null; then
        util.log.error "Please install GitHub/CLI/CLI (official), see"
        util.log.error "https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian-ubuntu-linux-apt"
        util.log.error "or simply: brew install gh"
        exit 40
    fi
    # if ! command -v hub --version 1>/dev/null; then
    #     util.log.error "Please install GitHub/Hub releases management CLI, see"
    #     util.log.error "https://github.com/github/hub#installation"
    #     exit 30
    # fi
}

ensure_github_cli_releases

#--------------------------------#
#--- Ensure Bash/Shell linter ---#
#--------------------------------#
## https://github.com/koalaman/shellcheck
function ensure_shellcheck_if_needed() {
    if test -n "$(find . -maxdepth 3 -name '*.sh' -print -quit)"; then
        if ! command -v shellcheck --version 1>/dev/null 2>&1; then
            util.log.error "Shell/Bash found on this project but shellcheck is not installed."
            util.log.error "  https://github.com/koalaman/shellcheck"
            util.log.error "  MacOS: brew install shellcheck"
            util.log.error "  Linux: snap install --channel=edge shellcheck"
            util.log.error "  Linux: sudo apt install shellcheck"
            util.log.error "  AnyOS: pip install shellcheck-py"
            exit 35
        fi
    else
        util.log.info "This project doesn't seem to be using Bash/Shell files."
    fi
}

ensure_shellcheck_if_needed

#--------------------------------#
#--- Ensure Dockerfile linter ---#
#--------------------------------#
## https://github.com/hadolint/hadolint
function ensure_hadolint_if_needed() {
    if test -n "$(find . -maxdepth 3 -name 'Dockerfile*' -print -quit)"; then
        if ! command -v hadolint --version 1>/dev/null 2>&1; then
            util.log.error "Dockerfile(s) found on this project but hadolint is not installed."
            util.log.error "MacOS: brew install hadolint"
            util.log.error "https://github.com/hadolint/hadolint#install"
            exit 40
        fi
    else
        util.log.info "This project doesn't seem to be using Dockerfile(s)."
    fi
}

ensure_hadolint_if_needed

#--------------------------------#
#--- Ensure Kubernetes linter ---#
#--------------------------------#
## https://github.com/stackrox/kube-linter
function ensure_kube_linter_if_needed() {
    # If there are yaml files containing both `apiVersion:` and `kind:` then is very likely this project contains K8s manifests
    if test -n "$(find . -name '*.yaml' -type f -exec grep -qlm1 'apiVersion:' {} \; -exec grep -lm1 -H 'kind:' {} \; -a -quit)"; then
        if ! command -v kube-linter version 1>/dev/null 2>&1; then
            util.log.error "Kubernetes manifest(s) found on this project but kube-linter is not installed."
            util.log.error "MacOS: brew install kube-linter"
            util.log.error "Linux: GO111MODULE=on go install golang.stackrox.io/kube-linter/cmd/kube-linter@latest"
            util.log.error "https://github.com/stackrox/kube-linter#installing-kubelinter"
            exit 42
        fi
        # KubeAudit doesn't lint, focuses more on security of running clusters
        # if ! command -v kubeaudit version 1>/dev/null 2>&1; then
        #     util.log.error "Kubernetes manifest(s) found on this project but kubeaudit is not installed."
        #     util.log.error "MacOS: brew install kubeaudit"
        #     util.log.error "Linux: https://github.com/Shopify/kubeaudit/releases"
        #     exit 44
        # fi
        #
        # KubeScore doesn't work with CDP templating system, yields errors like `Invalid value: "{{{APPLICATION_ID}}}"`
        # if ! command -v kube-score version 1>/dev/null 2>&1; then
        #     util.log.error "Kubernetes manifest(s) found on this project but kube-score is not installed."
        #     util.log.error "MacOS: brew install kube-score"
        #     util.log.error "Linux: https://github.com/zegl/kube-score/releases"
        #     exit 44
        # fi
        #
        # Polaris doesn't work with CDP templating system and fails without outputting offending lines
        # if ! command -v polaris version 1>/dev/null 2>&1; then
        #     util.log.error "Kubernetes manifest(s) found on this project but polaris is not installed."
        #     util.log.error "MacOS: brew tap FairwindsOps/tap && brew install FairwindsOps/tap/polaris"
        #     util.log.error "Linux: https://github.com/fairwindsops/polaris/releases"
        #     exit 44
        # fi
    else
        util.log.info "This project doesn't seem to be using Kubernetes manifests."
    fi
}

ensure_kube_linter_if_needed

#-----------------------------------#
#--- Ensure Ansible Dependencies ---#
#-----------------------------------#
## Ensure Ansible Galaxy roles (dependencies) are downloaded and up to date.
# Ansible Galaxy is the way to share Ansible PlayBooks with the open source community.
function ensure_ansible_if_needed() {
    if [ -f "ansible.cfg" ]; then
        if ! command -v ansible-galaxy --version 1>/dev/null; then
            util.die "ansible.cfg file found in this project but ansible-galaxy is not installed."
        fi
        # `ansible-galaxy`: command to manage Ansible roles in shared repositories,
        # the default of which is Ansible Galaxy https://galaxy.ansible.com
        # if [ -f "config/requirements.yml" ]; then
        #     util.log.info "Ensure Ansible Galaxy config (dependencies) are downloaded and up to date..."
        #     ansible-galaxy -vvv collection install --force -i -r config/requirements.yml
        #     ansible-galaxy -vvv role install --force -i -r config/requirements.yml
        # else
        #     util.log.info "No config/requirements.yml found to ansible-galaxy install."
        # fi
        if [ -f "roles/requirements.yml" ]; then
            util.log.info "Ensure Ansible Galaxy roles (dependencies) are downloaded and up to date..."
            ansible-galaxy -vvv collection install --force -r roles/requirements.yml
            ansible-galaxy -vvv role install --force -r roles/requirements.yml
        else
            util.log.info "No roles/requirements.yml found to ansible-galaxy install."
        fi
    else
        util.log.info "This project doesn't seem to be using Ansible."
    fi
}

ensure_ansible_if_needed

#----------------------------------------#
#--- Ensure Vagrant for local testing ---#
#----------------------------------------#
function ensure_vagrant_if_needed() {
    if test -n "$(find . -maxdepth 3 -name 'Vagrantfile*' -print -quit)"; then
        if ! command which vagrant 1>/dev/null; then
            util.log.error "Vagrantfile(s) found on this project but vagrant is not installed."
            util.log.error "https://www.vagrantup.com/docs/installation"
            exit 50
        fi
    else
        util.log.info "This project doesn't seem to be using Vagrantfile(s)."
    fi
}

ensure_vagrant_if_needed

#----------------------------------------#
#--- Ensure PyInvoke and invoke tests ---#
#----------------------------------------#
## https://github.com/pyinvoke/invoke
function ensure_pyinvoke_if_needed() {
    if [ -f "tasks.py" ] || [ -f "invoke.yaml" ]; then
        # let's make sure `poetry run` and `invoke` work
        if ! poetry run invoke setup; then
            util.die "Failed to poetry run invoke setup"
        fi
        # let's make sure we don't need `poetry run` since the .venv is activated anyways
        if ! invoke hooks; then
            util.die "Failed to run hooks"
        fi
        if [ -d 'tests' ] && ! invoke tests; then
            util.die "Failed to run tests"
        fi
    else
        util.log.info "This project doesn't seem to be using pyinvoke."
    fi
}

ensure_pyinvoke_if_needed

#-----------------------------------------#
#--- Ensure NodeJS for MkDocs JS needs ---#
#-----------------------------------------#
## https://github.com/DavidAnson/markdownlint
function ensure_nodejs_if_needed() {
    if [ -f "mkdocs.yml" ] || [ -f "docs/robots.txt" ]; then
        if ! command node --version 1>/dev/null 2>&1; then
            util.log.error "Please install NodeJS or put it in the PATH."
            util.log.error "  MacOS: brew install node"
            util.log.error "  Linux: apt -qyy install nodejs"
            exit 54
        fi
        if ! command npm --version 1>/dev/null 2>&1; then
            util.log.error "Please install NPM or put it in the PATH."
            util.log.error "  MacOS: brew install npm"
            util.log.error "  Linux: apt -qyy install npm"
            exit 55
        fi
    else
        util.log.info "This project doesn't seem to need NodeJS."
    fi
}

ensure_nodejs_if_needed

#------------#
#--- DONE ---#
#------------#
util.log.info ""
util.log.info "#----------------------------------------------#"
util.log.info "# SUCCESS! Now activate your environment with: #"
util.log.info "#     source .venv/bin/activate                #"
util.log.info "#----------------------------------------------#"
