# Xmip Handler Lineage

Xmip handlers and adapters are loadable modules.

Some handlers belong to the same technology family and share behavior, configuration concepts, operational constraints, or protocol expectations.

Xmip shall support this through handler lineage.

## Example

FTP is a base family.

SFTP and FTPS are derived handlers in the FTP family.

Conceptually:

```text
FTP family
    FTP
        SFTP
        FTPS
```

This does not require object-oriented source-code inheritance.

It means the loadable module manifest can declare:

- family,
- base component id,
- derived-from component ids,
- supported technologies.

## Kernel rule

The Xmip Kernel shall not hard-code FTP, SFTP, or FTPS behavior.

The Kernel reads handler metadata and applies common platform rules:

- loadability,
- compatibility,
- trust,
- isolation,
- ownership,
- audit,
- tracing,
- tracking,
- configuration binding.

Technology-specific behavior remains inside loadable handlers.

## Principle

Handler lineage expresses capability inheritance and family relationship.

It must not force the Xmip Kernel to understand technology internals.
