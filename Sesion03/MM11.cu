#include <stdio.h>
#include <stdlib.h>

#define SIZE 32

#ifndef PINNED
#define PINNED 0
#endif


// Matriz por Matriz
// C(NxM) <- A(NxP) * B (PxM)

//X = altura matriz A
//Y = ancho matriz A

//Y = altura matriz B
//Z = ancho matriz B


__global__ void Kernel00 (int X, int Y, int Z, float *A, float *B, float *C) {

  __shared__ float sA[SIZE][SIZE];
  __shared__ float sB[SIZE][SIZE];

  int row = blockIdx.y * blockDim.y + threadIdx.y;
  int col = blockIdx.x * blockDim.x + threadIdx.x;
  int iter = Y/SIZE + (Y%SIZE != 0);
  
  float tmp = 0.0;
  for (int m = 0; m < iter; m++){

   if (row < X && (m*SIZE + threadIdx.x) < Y)   
     sA[threadIdx.y][threadIdx.x] = A[row * Y + m*SIZE + threadIdx.x]; 
   else 
     sA[threadIdx.y][threadIdx.x] = 0;
   
   if (col < Z && (m*SIZE + threadIdx.y) < Y) 
     sB[threadIdx.y][threadIdx.x] = B[SIZE*Z*m + col + threadIdx.y*Z];
   else 
     sB[threadIdx.y][threadIdx.x] = 0;
   
   __syncthreads();


   if (col < Z && row < X) { 
     for (int k=0; k<SIZE; k++)
       tmp += sA[threadIdx.y][k] * sB[k][threadIdx.x];
   }
   __syncthreads();
  }
  if (col < Z && row < X) C[row*Z+col] = tmp;
  
}



void InitM(int N, int M, float *Mat);
int TestMM(int N, int M, int P, float *A, float *B, float *C);


// Invocacion:
// ./ejecutable TAM test
// TAM es el la dimension de las matrices
// test == 'Y', comprueba que el resultado sea correcto
// test == 'N', NO comprueba que el resultado (Util para tomar tiempos)
// Por defecto, N = 2048, test == 'N'

int main(int argc, char** argv)
{
  unsigned int N;
  unsigned int numBytes;
  unsigned int nBlocks, nThreads;
 
  float TiempoTotal, TiempoKernel;
  cudaEvent_t E0, E1, E2, E3;

  float *h_A, *h_B, *h_C;
  float *d_A, *d_B, *d_C;

  char test;

  // Dimension de las matrices NxN y comprobacion resultado
  if (argc == 1)      { test = 'N'; N = 2048; }
  else if (argc == 2) { test = 'N'; N = atoi(argv[1]); }
  else if (argc == 3) { test = *argv[2]; N = atoi(argv[1]); }
  else { printf("Usage: ./exe TAM test\n"); exit(0); }

  // numero de Threads en cada dimension 
  nThreads = SIZE;

  // numero de Blocks en cada dimension 
  nBlocks = N/nThreads + (N%nThreads != 0);
  
  numBytes = N * N * sizeof(float);

  dim3 dimGrid(nBlocks, nBlocks*2, 1);
  dim3 dimBlock(nThreads, nThreads, 1);

  cudaEventCreate(&E0);
  cudaEventCreate(&E1);
  cudaEventCreate(&E2);
  cudaEventCreate(&E3);

  if (PINNED) {
    // Obtiene Memoria [pinned] en el host
    cudaMallocHost((float**)&h_A, numBytes); 
    cudaMallocHost((float**)&h_B, numBytes); 
    cudaMallocHost((float**)&h_C, numBytes); 
  }
  else {
    // Obtener Memoria en el host
    h_A = (float*) malloc(numBytes); 
    h_B = (float*) malloc(numBytes); 
    h_C = (float*) malloc(numBytes); 
  }

  // Inicializa las matrices
  InitM(N, N, h_A);
  InitM(N, N, h_B);

  cudaEventRecord(E0, 0);
  cudaEventSynchronize(E0);
  
  // Obtener Memoria en el device
  cudaMalloc((float**)&d_A, numBytes); 
  cudaMalloc((float**)&d_B, numBytes); 
  cudaMalloc((float**)&d_C, numBytes); 

  // Copiar datos desde el host en el device 
  cudaMemcpy(d_A, h_A, numBytes, cudaMemcpyHostToDevice);
  cudaMemcpy(d_B, h_B, numBytes, cudaMemcpyHostToDevice);

  cudaEventRecord(E1, 0);
  cudaEventSynchronize(E1);
  
  // Ejecutar el kernel 
  Kernel00<<<dimGrid, dimBlock>>>(N, N, N, d_A, d_B, d_C);

  cudaEventRecord(E2, 0);
  cudaEventSynchronize(E2);

  // Obtener el resultado desde el host 
  cudaMemcpy(h_C, d_C, numBytes, cudaMemcpyDeviceToHost); 

  // Liberar Memoria del device 
  cudaFree(d_A);
  cudaFree(d_B);
  cudaFree(d_C);

  cudaEventRecord(E3, 0);
  cudaEventSynchronize(E3);

  cudaEventElapsedTime(&TiempoTotal,  E0, E3);
  cudaEventElapsedTime(&TiempoKernel, E1, E2);
  printf("\nKERNEL 00\n");
  printf("Dimensiones: %dx%d\n", N, N);
  printf("nThreads: %dx%d (%d)\n", nThreads, nThreads, nThreads * nThreads);
  printf("nBlocks: %dx%d (%d)\n", nBlocks, nBlocks, nBlocks*nBlocks);
  if (PINNED) printf("Usando Pinned Memory\n");
         else printf("NO usa Pinned Memory\n");
  printf("Tiempo Global: %4.6f milseg\n", TiempoTotal);
  printf("Tiempo Kernel: %4.6f milseg\n", TiempoKernel);
  printf("Rendimiento Global: %4.2f GFLOPS\n", (2.0 * (float) N * (float) N * (float) N) / (1000000.0 * TiempoTotal));
  printf("Rendimiento Kernel: %4.2f GFLOPS\n", (2.0 * (float) N * (float) N * (float) N) / (1000000.0 * TiempoKernel));

  cudaEventDestroy(E0); cudaEventDestroy(E1); cudaEventDestroy(E2); cudaEventDestroy(E3);

  if (test == 'N')
    printf ("NO TEST\n");
  else  if (TestMM(N, N, N, h_A, h_B, h_C))
    printf ("TEST PASS\n");
  else
    printf ("TEST FAIL\n");

  if (PINNED) {
    cudaFreeHost(h_A); cudaFreeHost(h_B); cudaFreeHost(h_C);
  }
  else {
    free(h_A); free(h_B); free(h_C);
  }

}


void InitM(int N, int M, float *Mat) {
   int i;
   for (i=0; i<N*M; i++) 
     Mat[i] = rand() / (float) RAND_MAX;
   
}

int error(float a, float b) {
  float tmp;

  tmp = abs(a-b) / abs(min(a,b));

  if (tmp > 0.0001) return 1;
  else  return 0;

}

int TestMM(int N, int M, int P, float *A, float *B, float *C) {
   int i, j, k;
   float tmp;
   for (i=0; i<N; i++)
     for (j=0; j<M; j++) {
       tmp = 0.0;
       for (k=0; k<P; k++) 
         tmp = tmp + A[i*P+k] * B[k*M+j]; 
       if (error(tmp, C[i*M+j])) {
         printf ("%d:%d: %f - %f = %f \n", i, j, tmp, C[i*M+j], abs(tmp - C[i*M+j]));
         return 0;
       }
     }
   
   return 1;
}
