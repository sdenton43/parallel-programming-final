#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
#include <iostream>
#include <math.h>
#include <cstdlib>

#define TIMING
#define MIN_SIZE 250000
#define SIZE_INCREMENT 250000
#define MAX_SIZE 10000000
#define SAMPLE_SIZE 1

#ifdef TIMING
double avgCPUTime, avgGPUTime;
double cpuStartTime, cpuEndTime;
#endif // TIMING

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

void writeheader(int N, int end) {
	FILE *fp;
	fp = fopen("outfile.pgm", "w");
	if (fp == NULL) {
		printf("sorry can't open outfile.pgm. Terminating.\n");
		exit(1);
	}
	else {
		// print a table header
		fprintf(fp, "%s\n%d %d\n%s\n", "P2", N, end, "255");
		fclose(fp);
	}
}

void writerow(int N, double rawdata[]) {
	FILE *fp;
	fp = fopen("outfile.pgm", "a");
	if (fp == NULL) {
		printf("sorry can't open outfile.pgm. Terminating.\n");
		exit(1);
	}
	else {
		for (int i = 0; i < N; i++) {
			int val = rawdata[i] * 127 + 127;
			fprintf(fp, "%d ", val);
		}
		fprintf(fp, "\n");
		fclose(fp);
	}
}

__host__
__device__
double initialCondition(double x, double y) {
	//double sigma=0.01;//tight point
	double sigma=0.1;//wider point
	double mu=0.5;//center
	double max = (1.0/(2.0*M_PI*sigma*sigma))*exp(-0.5*( ((0.5-mu)/sigma)*((0.5-mu)/sigma) +  ((0.5-mu)/sigma)*((0.5-mu)/sigma)   ));
	double result = (1.0/(2.0*M_PI*sigma*sigma))*exp(-0.5*( ((x-mu)/sigma)*((x-mu)/sigma) +  ((y-mu)/sigma)*((y-mu)/sigma)   ))/max;
	return result;
}


__host__
__device__
double f(int x, int y, int n, double* arr1, double* arr0) {
  //Blindly trust that his is right...
  double ans = (.01*(arr[(x-1)+(n*(y))] + arr[(x+1)+(n*(y))] + arr[(x)+(n*(y-1))] + arr[(x)+(n*(y+1))] - (4*arr[(x)+(n*(y))]))+((2*arr[(x)+(n*(y))])-arr2[(x)+(n*(y))]));
    return ans;
}


__global__
void wave(int n, double *arr0, double* arr1, double* arr2) {
	int id = threadIdx.x + blockDim.x*blockIdx.x;
	int stride = gridDim.x*blockDim.x;
	for (int i = id; i < n; i += stride) {
	  for(int j = id; j < n; j += stride) {
	    if(i== n-1 || i==0 || j == 0 || j == n-1){
	      arr2[(i*n)+j] = 0;
	    }else{
	      arr2[(i*n)+j] = f(j, i, n, arr1, arr0);
	    }
	  }
	}
}

__global__
void initForWave(double startX, double endX, int n, double* arr0, double* arr1, double* arr2) {
    for(int i = 0; i < n; i ++){
      for(int j = 0; j < n; j ++){
	arrZ[(i*n)+j] = initialCondition(((double)i)/(n-1),((double)j)/(n-1));
	arrO[(i*n)+j] = arr0[(i*n)+j];
	printf("%f" , arr0[(i*n)+j]);
      }
      printf("\n");
    }
}



int main(void) {
	int output = 1;
	cudaDeviceReset();
	cudaEvent_t start, stop;
	int n = 100;
	int N = n*n; // 1M elements
	int steps = 10;
	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	double *arr0; //= new float[N];
	double *arr1; //= new float[N];
	double *arr2; //= new float[N];
	double *temp, *localArr0;
	cudaEventRecord(start);
	localArr0 = (double*)malloc(N * sizeof(double));
	cudaMalloc(&arr0, N * sizeof(double));
	cudaMalloc(&arr1, N * sizeof(double));
	cudaMalloc(&arr2, N * sizeof(double));
	if (output == 1) {
		writeheader(N, steps);
	}

	int threadBlockSize = 128;
	int numThreadBlocks = (N + threadBlockSize - 1) / threadBlockSize;
	cudaDeviceSynchronize();
	initForWave << <numThreadBlocks, threadBlockSize >> >(0.0, 1.0, n, arr0, arr1, arr2);

	if (output == 1) {
			cudaMemcpy((void*)localArr0, (void*)arr0, N * sizeof(double), cudaMemcpyDeviceToHost);
			writerow(N, localArr0);
		}

	// Run kernel on 1M elements on the CPU
	for (int i = 0; i < steps; i++) {
		wave<<<numThreadBlocks, threadBlockSize>>>(N, arr0, arr1, arr2);
		cudaDeviceSynchronize();
		temp = arr0;
		arr0 = arr1;
		arr1 = arr2;
		arr2 = temp;

		if (output == 1) {
			cudaMemcpy((void*)localArr0, (void*)arr0, N * sizeof(double), cudaMemcpyDeviceToHost);
			writerow(N, localArr0);
		}
	}
	cudaEventRecord(stop);

	cudaEventSynchronize(stop);
	float elapsedTime;
	cudaEventElapsedTime(&elapsedTime, start, stop);

	free(localArr0);
	cudaFree(arr0);
	cudaFree(arr1);
	cudaFree(arr2);

	return 0;
}