# GitPack

GitPack is a Ruby program that allows you to install (`add`) and uninstall (`rm`) software directly from repositories containing a `.gitpack.yaml` manifest file.

## Features

- **Install Software**: Download and install software from GitHub repositories.
- **Uninstall Software**: Remove installed software using the same repository.
- **Manifest-Driven**: Only requires a `.gitpack.yaml` manifest file in the repository.

## Installation

### With Make

1. Ensure you have Ruby installed on your system.
2. Clone this repository:

    ```bash
    git clone https://github.com/juliankahlert/gitpack.git
    ```

3. Navigate to the `gitpack` directory:

    ```bash
    cd gitpack
    ```

4. Install `gitpack`:

    ```bash
    sudo make install
    ```

### With GitPack

```bash
sudo gitpack add juliankahlert/gitpack@main
```

## Usage

### Install a Package

To install a package from a GitHub repository, use the `add` command:

```bash
gitpack add <user>/<repo>[@<branch>]
```

- `<user>`: GitHub username or organization name.
- `<repo>`: Repository name.
- `@<branch>`: (Optional) Specific branch to install from. Defaults to `main` if not specified.

**Example:**

```bash
sudo gitpack add juliankahlert/gitpack@main
```

### Uninstall a Package

To uninstall a package using the same repository, use the `rm` command:

```bash
gitpack rm <user>/<repo>[@<branch>]
```

**Example:**

```bash
sudo gitpack rm juliankahlert/gitpack@main
```

### Accessing private Repositories

To access private repositories the `--token PRIVATE_ACCESS_TOKEN` can be used.

```bash
gitpack --token <PRIVATE_ACCESS_TOKEN> add <user>/<repo>[@<branch>]
```

**Example:**

```bash
sudo gitpack --token <PRIVATE_ACCESS_TOKEN> add juliankahlert/gitpack@main
```

## Manifest File

The `.gitpack.yaml` manifest file defines the actions for installing and uninstalling the software. It should be located in the root of the repository. The file structure is as follows:

```yaml
gitpack:
  name: "Example Package"
  category: lib
  files:
    - "{{prefix}}/bin/example"
  add:
    - sh:
        - "make install PREFIX={{prefix}}"
  rm:
    - remove_files
```

- **name**: The name of the package.
- **category**: The category of the package.
- **files**: List of files to be installed, using `{{prefix}}` as the installation prefix.
- **add**: List of actions to execute during installation.
  - **sh**: List of shell commands to run for installation.
- **rm**: List of actions to execute during uninstallation.
  - **remove_files**: Special action to remove all listed files.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any improvements or bug fixes.

## Disclaimer

This software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
