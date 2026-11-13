%% 说明: 使用自行编写的FFT，将CMA_reference.m中的核心算法在频域下实现
clc;
clear;
close all;
%% Load Datas from Timing Recovery
load TD_TRdata.mat;
SigX_in = RTdataX;
SigY_in = RTdataY;

figure();
subplot(121);plot(RTdataX,'.r');title('Xpol before CMA');xlim([-2 2]);ylim([-2 2]);
subplot(122);plot(RTdataY,'.b');title('Ypol before CMA');xlim([-2 2]);ylim([-2 2]);


%% 第一步 DFT(FFT)

%% 第二步 将输入信号和均衡器抽头分别通过FFT转换到频域，利用 “频域乘积等效于时域卷积” 的特性，快速计算均衡后的输出信号；

%% 第三步 计算误差以及抽头更新


%% Figure and Results
figure();
subplot(121);plot(CMAdataX,'.r');title('Xpol after CMA');xlim([-2 2]);ylim([-2 2]);
subplot(122);plot(CMAdataY,'.b');title('Ypol after CMA');xlim([-2 2]);ylim([-2 2]);

CMAdataX=CMAdataX(end-131072:end);
CMAdataY=CMAdataY(end-131072:end);

figure();
subplot(121);plot(CMAdataX,'.r');title('Last part of Xpol after CMA');xlim([-2 2]);ylim([-2 2]);
subplot(122);plot(CMAdataY,'.b');title('Last part of Ypol after CMA');xlim([-2 2]);ylim([-2 2]);