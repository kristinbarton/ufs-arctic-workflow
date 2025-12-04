import numpy as np
import argparse
import netCDF4 as nc
from netCDF4 import Dataset

def main(args):
    thk_var = args.thickness_variable
    filename = args.file_name
    time_dim = args.time_dim
    eta_var = 'eta'

    with Dataset(filename, 'a', format='NETCDF4') as ds:
        if thk_var not in ds.variables:
            raise KeyError(f"Variable '{thk_var}' not found in file '{filename}'.")

        thk = ds[thk_var][:,:,:,:]
        [nt, nz, ny, nx] = thk.shape

        eta = np.zeros([nt, nz+1, ny, nx])
        eta[0,0,:,:] = thk[0,0,:,:]

        for k in range(nz):
            eta[0,k+1,:,:] = eta[0,k,:,:] - thk[0,k,:,:]

        if 'zp' not in ds.dimensions:
            ds.createDimension('zp', nz+1)
        if eta_var not in ds.variables:
            var = ds.createVariable(eta_var, 'f4', (time_dim, 'zp', 'yh', 'xh'), fill_value=1.e+20)
            var[:,:,:,:] = eta[:,:,:,:]
        else:
            var = ds.variables[eta_var]
            var[:,:,:,:] = eta[:,:,:,:]

if __name__=="__main__":
    parser = argparse.ArgumentParser(description="Add eta to existing IC file.")

    # Required Arguments
    parser.add_argument("--file_name", required=True)
    parser.add_argument("--thickness_variable", required=True)
    parser.add_argument("--time_dim", required=True)

    args = parser.parse_args()  

    main(args)
