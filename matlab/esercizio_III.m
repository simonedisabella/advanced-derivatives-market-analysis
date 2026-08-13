clc; clear all

% Carica file Excel
Tcall=readtable("Dataset.xlsx", "Sheet", 1);
Tput=readtable("Dataset.xlsx", "Sheet",2);
TEuroStoxx=readtable("EUSTX.xlsx");
ESprice=TEuroStoxx.Price;

q=2.78/100;
S0=ESprice(1,1);
T=36/365;
Sigma=0.07;
Kstar=5740;
ImplVolCall=Tcall.IVM/100; %la volatilità diminuisce all'aumentare dello strike
Kcall=Tcall.Strike;

% Calcolo valori Mid
CallBid=Tcall.Bid;
CallAsk = Tcall.Ask; 
PutBid=Tput.Bid;
PutAsk=Tput.Ask;
CallMid=(CallBid+CallAsk)/2;
PutMid = (PutBid + PutAsk) / 2;

%% Boostrap dello zero rate a 1 mese partendo dalla curva EUR OIS
TOIS = readtable("curvaEUROIS.xlsx", "VariableNamingRule","preserve");
tau=30/360; % year fraction

% identificazione celle tasso OIS a un mese e calcolo del tasso mid
TenorValue = TOIS.("Term");                 
TenorUnit  = string(TOIS.("Unit"));         
% Pulizia robusta: tolgo apostrofi e spazi
TenorUnit = erase(TenorUnit, "'");         
TenorUnit = strtrim(TenorUnit);             
% Trovo 1 MO
idx1M = find(TenorValue == 1 & TenorUnit == "MO", 1);
% Estraggo Final Bid/Ask Rate
R_bid = TOIS{idx1M, "Final Bid Rate"} / 100;
R_ask = TOIS{idx1M, "Final Ask Rate"} / 100;
Rois_1M = (R_bid + R_ask)/2;


% La maturity dell'OIS è a 1 mese, quindi il contratto prevede un solo flusso, posso usare la formula per le meturity brevi
DF0_T=1/(1+Rois_1M*tau);
% Estraggo lo zero rate ipotizzando la capitalizzaizone continua
z_1M = -log(DF0_T)/tau;
% lo identifico con r per comodità
r=z_1M;


%% Metodo Mc per il prezzo della Call con K=5740
Nsim=20000;
Z=randn(Nsim,1); %sto simulando 20000 valori da una normale std
Si=S0*exp((r-q-0.5*Sigma^2)*T+Sigma*T^0.5*Z);
Payoffi=max(Si-Kstar,0); 
Ci=Payoffi*exp(-r*T);
[Cmc,Dev_Cmc, IC_Cmc]=normfit(Ci); %calcolo del prezzo, della deviazione std e dell'IC dell'opzione tramite simulazione MonteCarlo
%L'intervallo di confidenza al 95% è costruito sfruttando il Teorema del Limite Centrale applicato alla media dei payoff scontati

%% Valutazione dell'opzione con K=5740 con formula BS e stima della volatilità implicita, con campione composto solo da call OTM

% Identifico le call OTM e utilizzo solo loro come campione per la regressione
idxOTM_call = Tcall.Strike >= S0;
Tcall_OTM = Tcall(idxOTM_call, :);

% Stima della volatilità implicita
KcallOTM = Tcall_OTM.Strike;          % strike call OTM
ImplVolCallOTM = Tcall_OTM.IVM / 100;   % volatilità implicita call OTM

vCallOTM = ImplVolCallOTM * sqrt(T);
Atab = regstats(vCallOTM, KcallOTM, 'purequadratic');
A = Atab.beta;

vStar = A(1) + A(2)*Kstar + A(3)*(Kstar^2);
ImplSigmaStar = vStar / sqrt(T);


% Calcolo del prezzo della Call con la formula di Black-Scholes
Cbs=BSPrice(S0,Kstar,r,q,T,ImplSigmaStar,"C");

%% Confronto del prezzo dell'opzione con BS e metodo Monte Carlo mediante l'utilizzo dello stesso valore di volatilità
 
% Utilizzo della volatilità ottenuta tramite interpolazione
Cbs_volINT=Cbs;
Si_volINT=S0*exp((r-q-0.5*ImplSigmaStar^2)*T+ImplSigmaStar*T^0.5*Z);
Payoffi_volINT = max(Si_volINT - Kstar, 0);
Ci_volINT = Payoffi_volINT * exp(-r*T);
Cmc_volINT = mean(Ci_volINT);

% Utilizzo della volatilità data dal testo(sigma=0,07)
Cmc_volTXT=Cmc;
Cbs_volTXT=BSPrice(S0,Kstar,r,q,T,Sigma,"C");

% Presentazione dei risultati
fprintf('Prezzo Call con BS (volatilità test): %.4f\n', Cbs_volTXT);
fprintf('Prezzo Call con Monte Carlo (volatilità test): %.4f\n', Cmc_volTXT);
fprintf('Prezzo Call con Monte Carlo (volatilità interpolata): %.4f\n', Cmc_volINT);
fprintf('Prezzo Call con BS (volatilità interpolata): %.4f\n', Cbs_volINT);
fprintf('Intervallo di confidenza al 95%%: [%.4f, %.4f]\n', IC_Cmc(1), IC_Cmc(2));


%%  Confronto grafico BS vs MC

Prezzi = [Cbs_volTXT, Cmc_volTXT;
          Cbs_volINT, Cmc_volINT];

figure;
bar(Prezzi);
set(gca,'XTickLabel',{'σ test','σ interpolata'});
legend('Black–Scholes','Monte Carlo','Location','northwest');
ylabel('Prezzo della Call');
title('Confronto prezzi BS vs MC a parità di volatilità');
grid on;
