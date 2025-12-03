import numpy as np
import xarray as xr

def main():
    old_ds = xr.open_dataset("ocean_topog.nc")
    new_ds = xr.open_dataset("remap.ocean_topog.nc")

    old_depth = old_ds['depth'].values[:]
    new_depth = new_ds['depth'].values[:]

    new_ds['depth'][:] = np.where((old_depth>1.0)&(new_depth>1.0), new_depth, old_depth)

    new_ds.to_netcdf("patch.ocean_topog.nc")

if __name__=="__main__":
    main()
