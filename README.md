ehpas_report
============
This adds a custom report processor based on tagmail. It's just to show that reports can be handled in 
various ways.

Put this module in your module path and in /etc/puppetlabs/puppet/puppet.conf add ehpas to your reports line.
example:
```
reports = console,puppetdb,ehpas
```

Use the ehpas tag on your resources and voila!

