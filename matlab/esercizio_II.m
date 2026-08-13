clc; clear all

% Carica file Excel
Tcall=readtable("Dataset.xlsx", "Sheet", 1);
Tput=readtable("Dataset.xlsx", "Sheet",2);
TEuroStoxx=readtable("EUSTX.xlsx");
ESprice=TEuroStoxx.Price;

r=1.95634/100;  % Zero rate a un mese osservato su Bloomber
q=2.78/100; 
S0=ESprice(1,1);
T=36/365;
ImplVolCall=Tcall.IVM/100; %la volatilità diminuisce all'aumentare dello strike
Kcall=Tcall.Strike;

% Calcolo valori Mid
CallBid=Tcall.Bid;
CallAsk = Tcall.Ask; 
PutBid=Tput.Bid;
PutAsk=Tput.Ask;
CallMid=(CallBid+CallAsk)/2;
PutMid = (PutBid + PutAsk) / 2;

% Identifico le call OTM e utilizzo solo loro come campione per la regressione
idxOTM_call = Tcall.Strike >= S0;
Tcall_OTM = Tcall(idxOTM_call, :);

%  Variabili per la regressione
Kcall = Tcall_OTM.Strike;          % strike call OTM
sigmaCall = Tcall_OTM.IVM / 100;   % volatilità implicita call OTM

%  Calcolo v(K) = sigma(K) * radice(T)
vCall = sigmaCall * sqrt(T);

%  Regressione OLS quadratica su v(K)
% v(K) = A0 + A1K + A2K^2
Reg = regstats(vCall, Kcall, 'purequadratic');
beta = Reg.beta;

% Valutazione per Kstar
Kstar = 5753;
vStar = beta(1) + beta(2)*Kstar + beta(3)*(Kstar^2);

% Torno alla volatilità implicita
ImplVolStar = vStar / sqrt(T);

%  Prezzo della call con Black–Scholes
C_Kstar = BSPrice(S0, Kstar, r, q, T, ImplVolStar, "C");

%  Output finale
fprintf("Volatilità implicita interpolata (K=5753): %.4f\n", ImplVolStar);
fprintf("Prezzo della call con strike K=5753: %.4f\n", C_Kstar);


%%  Grafico dello smile

% Dati osservati
K_data = Kcall;
v_data = vCall;

% Vertice della parabola stimata
K_vert = -beta(2) / (2*beta(3));

% Ampiezza del dominio stabilita per garantire simmetria
L = max(abs(K_data - K_vert)) + 200;

% Dominio simmetrico attorno al vertice
Kgrid = linspace(K_vert - L, K_vert + L, 400)';

% Valori stimati
vHat = beta(1) + beta(2)*Kgrid + beta(3)*(Kgrid.^2);

figure;
plot(K_data, v_data, 'o', 'MarkerSize', 6); hold on;
plot(Kgrid, vHat, '-', 'LineWidth', 1.5);

xlabel('Strike K');
ylabel('v(K)');
title('Interpolazione quadratica di v(K)');
legend('Dati osservati (call OTM)', 'Regressione quadratica', 'Location', 'best');
grid on;







