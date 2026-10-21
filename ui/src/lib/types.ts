export type VehicleType = 'car' | 'offroad' | 'van' | 'truck' | 'motorcycle' | 'bicycle' | 'boat' | 'heli' | 'plane';
export type StockStatus = 'transit' | 'waiting' | 'pickup' | 'storage' | 'display' | 'testdrive' | 'out' | 'sold' | 'removed';
export type ShopType = 'npc' | 'player' | 'mixed';

export interface Vec4 { x: number; y: number; z: number; w?: number }

export interface ShopSettings {
  currency: string;
  npcPriceMultiplier: number;
  wholesaleMultiplier: number;
  mixedNpcMultiplier: number;
  minStaffOnline: number;
  commissionPercent: number;
  maxDiscountPercent: number;
  npcDelivery: boolean;
  storageLimit: number;
  dropoffRadius: number;
  npcModel: string;
  description: string;
  deliveryPoints: string[];
  blip: { enabled: boolean; sprite: number; color: number; scale: number };
  testDrive: { enabled: boolean; seconds: number; deposit: number };
  finance: { enabled: boolean; downPaymentPercent: number; installments: number; intervalMinutes: number; interestPercent: number };
  tradeIn: { enabled: boolean; npcPercent: number };
}

export interface ShopSummary {
  id: number;
  label: string;
  type: ShopType;
  job?: string | null;
  ownerId?: string | null;
  ownerName?: string | null;
  active: boolean;
  npcActive: boolean;
  staffOnDuty: number;
}

export type Flags = Record<string, boolean>;

export interface Meta {
  types: VehicleType[];
  categories: string[];
  statuses: StockStatus[];
  policyKeys: string[];
  points: Array<{ id: string; label: string; types: VehicleType[]; enabled: boolean }>;
  methods: string[];
  cancelFeePercent: number;
  contractsEnabled: boolean;
  maxMissed: number;
}

export interface Session {
  actor: { id: string; name: string; grade: number; gradeLabel: string; isBoss: boolean; isAdmin: boolean };
  shops: ShopSummary[];
  shop: ShopSummary;
  settings: ShopSettings;
  points: Partial<Record<'manage' | 'npc' | 'handover' | 'dropoff', Vec4>>;
  flags: Flags;
  strings: Record<string, string>;
  meta: Meta;
  dateTimeFormat?: { locale?: string; dateFormat?: string; timeFormat?: string };
  uiCache?: boolean;
  resourceVersion?: string;
}

export interface Condition { engine?: number; body?: number; fuel?: number; dirt?: number; tank?: number }

export interface ContractRef { id: number; status: string; reward: number; takerName?: string; deadlineAt?: number }

export interface StockItem {
  id: number;
  plate?: string | null;
  model: string;
  label: string;
  brand?: string;
  vtype: VehicleType;
  status: StockStatus;
  displayId?: number | null;
  displayLabel?: string | null;
  price: number;
  listPrice?: number;
  cost: number;
  condition?: Condition;
  source: string;
  deliveryPoint?: string | null;
  deliveryLabel?: string | null;
  eta: number;
  arrivedAt: number;
  orderedBy?: string | null;
  reservedFor?: string | null;
  reservedName?: string | null;
  note?: string | null;
  createdAt: number;
  updatedAt: number;
  contract?: ContractRef | null;
}

export interface StockDetail extends StockItem {
  damage: number;
  storageFee: number;
  history: Array<{ actor_name?: string; action: string; details_json?: string; created_at: number }>;
}

export interface DisplaySpot {
  id: number;
  label: string;
  types: VehicleType[];
  kind: 'stock' | 'showcase';
  turntable: boolean;
  sign: boolean;
  x: number;
  y: number;
  vehicle?: StockItem | null;
  showcase?: CatalogEntry | null;
}

export interface CatalogEntry {
  model: string;
  label: string;
  brand: string;
  category: string;
  vtype: VehicleType;
  price: number;
  wholesale?: number;
  minutes?: number | null;
  points?: string[];
  enabled?: boolean;
  blocked?: boolean;
  image?: string | null;
}

export interface Sale {
  id: number;
  plate?: string;
  model?: string;
  label?: string;
  price: number;
  cost: number;
  buyerName?: string;
  sellerName?: string;
  method: string;
  channel: string;
  commission: number;
  createdAt: number;
}

export interface DayStat { day: string; revenue: number; profit: number; count: number }

export interface Contract {
  id: number;
  shopId: number;
  stockId: number;
  reward: number;
  payout: number;
  status: string;
  note?: string;
  takerName?: string;
  takenAt: number;
  deadlineAt: number;
  createdBy?: string;
  createdAt: number;
  doneAt: number;
  vehicle?: { label: string; plate?: string; model: string; vtype: VehicleType; deliveryPoint?: string };
}

export interface TradeIn {
  id: number;
  plate: string;
  model: string;
  label: string;
  vtype: VehicleType;
  sellerName?: string;
  condition?: Condition;
  asking: number;
  offer: number;
  status: string;
  offeredBy?: string;
  createdAt: number;
  expiresAt: number;
  listPrice?: number;
  damage: number;
  suggestion?: number | null;
}

export interface Finance {
  id: number;
  plate?: string;
  label?: string;
  buyerName?: string;
  total: number;
  paid: number;
  rate: number;
  ratesLeft: number;
  intervalMin: number;
  nextDueAt: number;
  missed: number;
  status: 'active' | 'paid' | 'defaulted' | 'repossessed';
  createdAt: number;
}

export interface LedgerEntry { id: number; amount: number; balanceAfter: number; kind: string; text?: string; ref?: string; actor?: string; createdAt: number }

export interface Dashboard {
  balance?: number | null;
  counts: Record<string, number>;
  daily: DayStat[];
  recentSales: Sale[];
  arrivals: StockItem[];
  waiting: StockItem[];
  contractsOpen: number;
  tradeinsOpen: number;
  financeDefaulted: number;
  staffOnDuty: number;
  npcActive: boolean;
  displays: number;
  displaysUsed: number;
}

export interface NearbyPlayer { src: number; name: string; distance: number }

export interface FinancePlan { price: number; downPayment: number; financed: number; interest: number; total: number; installments: number; rate: number; intervalMinutes: number }
