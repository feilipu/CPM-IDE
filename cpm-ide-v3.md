The CP/M-IDE is an implementation of CP/M for the RC2014 platform. It supports a variety of hardware using different drivers for the underlying hardware

## current situation

Currently the CP/M-IDE uses a C shell to select a set of 4 live CP/M drive files, from a FATFS formatted file system. These selected CP/M drive files need to be formatted as CP/M compatible files. See the documentation for the CP/M drive file format specifics. Once the relevant files are selected a boot process loads CP/M into the RAM and then switches (via a moving ROM in lower 32kB to RAM in lower 32kb) to the CP/M BIOS BDOS and CCP to start running CP/M. The drive file LBA address (from which offsets are calculated) are found in an array of these addresses, which is passed to CP/M. On boot, the C shell initially copies the diskio and other functions to high memory on boot, and then uses them to enable its fatfs implementation ff to read the directory and identify the LBA of each CP/M drive file.

This requires the user to use the cpm-tools cli tool to create and use the CP/M-IDE drive files. Their internal structure cannot be seen by the FATFS host system. This is a limitation.

## project goal

The project goal is to convert the existing CP/M-IDE BIOS implementation to be able to read FATFS directories directly, from which CP/M binary and data files can be read directly. There should be no need to modify the BDOS or CCP, however if inconsistency or clear bugs are identified they should be called out.

As a decision, we need to allow the user to select one directory, wherein there are directories labeled A, B, C, D, etc, which are the live directories containing CP/M files. Or alternatively allow the user to select a number of directories which will be connected to the CP/M A, B, C, or D drives.

Noting that CP/M has no concept of directories, simply drives. There can be up to 16 drives, and they are lettered A through P maximally. Though the RAM buffer cost for each additional mounted drive is high so it makes sense to limit the maximum number of mounted drives.

So, as a decision, it would be ideal if the user could easily determine which directories are loaded at boot time via the same shell structure as currently, or via a default configuration file in a specific directory with relative directories associated with CP/M drive letters in a toml format.

As a mandatory goal we should also allow the CP/M BIOS to read and write 512 byte IDE files directly, rather than via the 128 byte CP/M standard. This will save one layer of buffer copy, and will save valuable RAM in the BIOS.

As a direction goal the BIOS disk interface implementation should be fast and optimised for speed, using partially unrolled LDI or synthetic unroll, as already in place, for buffer copy.

In order to avoid implementation cost, the z88dk-libraries ff implementation is used for the shell, so assembled versions of the ff fatfs implementation should be examined for shapes and code to implement the new bios functions. The minimum amount of ff functions (or ff derived functions) should be pulled into the new bios to allow read/write access to the disk via diskio function API.

The fatfs implementation uses diskio functions (see the documentation in the ff library), and these diskio functions are already used directly by the existing BIOS and by the C shell using the ff-ro versions of the ff library. Obviously, the ff-ro library versions cannot be used by the new BIOS implementation, as there is no file write capability included.

## hardware alternatives

There are both z80 and 8085 versions of the builds. The implementation needs to be ported with minimum adaption related to the hardware to support each of the combinations. z80 with ACIA, SIO and UART, with CF and IDE disk. 8085 with ACIA, UART, with CF and IDE disk. The existing set of sources attempt to do this with the minimum of changes.

There are a variety of serial interfaces, including the ACIA MC6850B, the Zilog SIO/2 chip and a number of UART chips (that are not fully working). On the 8085 also supports a bit-banged Serial Interface pin for output only.

There are two options for disk interfaces, either the 8-bit Compact Flash interface, and the 16-bit IDE interface. The interface is selected in z88dk newlib by a setting in the configuration files.

There is also a shadow ram setting for the z80 processor where a 128kB RAM card is selected. normally this is left off, though the support code remains.

## project references

See the readme file in the project directory.
https://github.com/feilipu/CPM-IDE/blob/cpm-ide-v3/README.md
This provides connection to hardware information on the RC2014 web site, which can be evaluated for details on hardware.

It further refers to a blog post that give more detail.
https://feilipu.me/2022/03/23/cpm-ide-for-rc2014/

CP/M specification can be found at seasip.
https://www.seasip.info/Cpm/
Detailed technical information on BDOS calls, API, and BIOS functions and their requirements can be obtained there. Any inconsistencies with the implementation in CP/M-IDE should be called out.

As a final reference the Digital Research implementation documents (in pdf format) can be read. This page summaries the links. Only read these pdf documents to clarify ambiguity.
http://www.primrosebank.net/computers/cpm/cpm_manuals.htm
Original source cpm.z80.de
CP/M 2.0 Interface Guide
CP/M 2.2 Alteration Guide
CP/M 2.2 Operating Manual
 
