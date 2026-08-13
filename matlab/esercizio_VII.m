clc; clear all

TOIS = readtable("curvaEUROIS.xlsx", "VariableNamingRule","preserve");

% identificazione colonne tasso OIS, e calcolo final mid rate
TenorValue = TOIS.("Term");                 
TenorUnit  = string(TOIS.("Unit"));         
% Pulizia robusta: tolgo apostrofi e spazi
TenorUnit = erase(TenorUnit, "'");         
TenorUnit = strtrim(TenorUnit); 
% calcolo final mid rate
% Estraggo Final Bid/Ask Rate
R_bid = TOIS{:,"Final Bid Rate"} / 100;
R_ask = TOIS{:,"Final Ask Rate"} / 100;
Rois_mid = (R_bid + R_ask)/2;

% Creazione vettore durata contratto OIS
MaturityGG=zeros(length(TenorValue),1);
for i=1:length(TenorValue)
 if TenorUnit(i,1)=="WK"
  MaturityGG(i,1)=TenorValue(i,1)*7;
 elseif TenorUnit(i,1)=="MO"
     MaturityGG(i,1)=TenorValue(i,1)*30;
 elseif TenorUnit(i,1)=="YR"
     MaturityGG(i,1)=TenorValue(i,1)*360; 
 end
end

%% Calcolo di tau tramite daycount convention, in tutto il dataset ho solo frequenze=1

MaturityYR = MaturityGG / 360; % Calcolo della maturity espressa in anni
% tau_k, ovvero la frazione di anno dei periodi di pagamento
tau = cell(length(MaturityYR),1);

for i = 1:length(MaturityYR)
 T = MaturityYR(i);
  if T < 1
   tau{i} = T; % Un solo pagamento a scadenza
  else
    % Pagamenti annuali (Freq = 1)
    n = floor(T);           % numero di anni interi
    stub = T - n;           % eventuale periodo finale
     if stub > 0
        tau{i} = [ones(n,1); stub];
     else
        tau{i} = ones(n,1);
      end
   end
end

%% Boostrapping discount factors distinguendo gli OIS con un solo pagamento e quelli con più pagamenti

% Inizializzazione vettore DF
DF = zeros(length(MaturityYR),1);

for i = 1:length(DF)
 if MaturityYR(i,1)<1 % Caso con maturity breve(un solo pagamento)
  DF(i,1)=1/(1+Rois_mid(i,1)*tau{i});
 else % Caso con maturity lunga(più pagamenti)
sumDF = 0;
taus = tau{i};
nPay = length(taus);

for k = 1:(nPay-1)
    t_k = k;  % tutti gli anni interi

    % interpolazione log-DF
    DF_interp = exp(interp1(MaturityYR(1:i-1), log(DF(1:i-1)), t_k, 'linear', 'extrap'));
    sumDF = sumDF + taus(k) * DF_interp;
end

tau_last = tau{i}(end);
DF(i) = (1 - Rois_mid(i)*sumDF) / (1 + Rois_mid(i)*tau_last);
  end
end

%% Calcolo degli zero rates in capitalizzazione continua e presentazione dei risultati

ZeroRate = -log(DF)./MaturityYR;
ZeroRate_perc=ZeroRate*100;

DataFrame_risultati = table(TenorValue, TenorUnit, DF, ZeroRate, ZeroRate_perc,'VariableNames', {'Term','Unit','Discount Factor','Zero Rate', 'Zero Rate %'});
disp(DataFrame_risultati)

%% Curva discount factor

figure;
plot(MaturityYR, DF, '-o','LineWidth', 1.5,'MarkerSize', 5);

xlim([0 50]);
ylim([0 1]);

xlabel('Maturity (years)');
ylabel('Discount Factor P(0,T)');
title('EUR OIS Discount Curve');

grid on;
set(gca,'FontSize',11);

%% Curva zero-rates

figure;
plot(MaturityYR, ZeroRate_perc,'-o','LineWidth', 1.5,'MarkerSize', 5);

xlim([0 50]);
ylim([1.8 3.2]);

xlabel('Maturity (years)');
ylabel('Zero rate (%)');
title('EUR OIS Zero Rate Curve (cont.)');

grid on;
set(gca,'FontSize',11);



