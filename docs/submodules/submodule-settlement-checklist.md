# Submodule Settlement Checklist

Run locally from the root `Xmip` repository.

## 1. Create missing family repositories

```powershell
pwsh ./scripts/git/New-XmipFamilyRepositories.ps1 -Owner IlleNilsson
```

## 2. Add root family submodules

```powershell
pwsh ./scripts/git/Add-XmipNestedSubmoduleFamilies.ps1 -Owner IlleNilsson
```

## 3. Add nested common handler submodules

```powershell
cd handlers/common
pwsh ../../scripts/git/Add-XmipCommonNestedSubmodules.ps1 -Owner IlleNilsson
cd ../..
```

## 4. Initialize recursively

```powershell
git submodule update --init --recursive
```

## 5. Review

```powershell
git submodule status --recursive
git status --short
```

## 6. Commit

```powershell
git add .gitmodules handlers core runtimes platforms
git commit -m "Settle Xmip nested submodules"
git push
```
