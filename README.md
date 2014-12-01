gsConfigPush
============

Push configuration settings to Grandstream GXP2120 phones via HTTP

Here is a simple bash script that logs into the web interface of a Grandstream IP phone and submits some configuration changes, and then reboots the device for the changes to take effect.

This was tested with a Grandstream GXP2120 on firmware versions 1.0.1.56, 1.0.1.64, 1.0.1.105, 1.0.4.23, and 1.0.6.7 might be adaptable for other Grandstream devices as well.

Grandstream has configuration templates for a number of devices.  You can download a zip archive of them from the following URL: http://www.grandstream.com/tools/GAPSLITE/config-template.zip

The configuration is made up of a pair of values, a P-code and the P-codes applicable value (Grandstream calls these P values in some of their documentation)

For more info check out the project blog: http://ethertubes.com/grandstream-simple-http-configuration-pusher/
